local cassandra = require "cassandra"
local Cluster   = require "resty.cassandra.cluster"


local CassandraConnector   = {}
CassandraConnector.__index = CassandraConnector


function CassandraConnector.new(kong_config)
  local cluster_options       = {
    shm                       = "kong_cassandra",
    contact_points            = kong_config.cassandra_contact_points,
    default_port              = kong_config.cassandra_port,
    keyspace                  = kong_config.cassandra_keyspace,
    timeout_connect           = kong_config.cassandra_timeout,
    timeout_read              = kong_config.cassandra_timeout,
    max_schema_consensus_wait = kong_config.cassandra_schema_consensus_timeout,
    ssl                       = kong_config.cassandra_ssl,
    verify                    = kong_config.cassandra_ssl_verify,
    cafile                    = kong_config.lua_ssl_trusted_certificate,
    lock_timeout              = 30,
    silent                    = ngx.IS_CLI,
  }

  if ngx.IS_CLI then
    local policy = require("resty.cassandra.policies.reconnection.const")
    cluster_options.reconn_policy = policy.new(100)

    -- Force LuaSocket usage in the CLI in order to allow for self-signed
    -- certificates to be trusted (via opts.cafile) in the resty-cli
    -- interpreter (no way to set lua_ssl_trusted_certificate).
    local socket = require "cassandra.socket"
    socket.force_luasocket("timer", true)
  end

  if kong_config.cassandra_username and kong_config.cassandra_password then
    cluster_options.auth = cassandra.auth_providers.plain_text(
      kong_config.cassandra_username,
      kong_config.cassandra_password
    )
  end

  if kong_config.cassandra_lb_policy == "RoundRobin" then
    local policy = require("resty.cassandra.policies.lb.rr")
    cluster_options.lb_policy = policy.new()

  elseif kong_config.cassandra_lb_policy == "DCAwareRoundRobin" then
    local policy = require("resty.cassandra.policies.lb.dc_rr")
    cluster_options.lb_policy = policy.new(kong_config.cassandra_local_datacenter)
  end

  local cluster, err = Cluster.new(cluster_options)
  if not cluster then
    return nil, err
  end

  local self   = {
    cluster    = cluster,
    keyspace   = cluster_options.keyspace,
    opts       = {
      write_consistency =
        cassandra.consistencies[kong_config.cassandra_consistency:lower()],
      read_consistency =
        cassandra.consistencies[kong_config.cassandra_consistency:lower()],
      serial_consistency = cassandra.consistencies.serial, -- TODO: or local_serial
    },
    connection = nil, -- created by connect()
  }

  return setmetatable(self, CassandraConnector)
end


local function extract_major(release_version)
  return string.match(release_version, "^(%d+)%.%d")
end


function CassandraConnector:init()
  local ok, err = self.cluster:refresh()
  if not ok then
    return nil, err
  end

  -- get cluster release version

  local peers, err = self.cluster:get_peers()
  if err then
    return nil, err
  end

  if not peers then
    return nil, "no peers in shm"
  end

  local major_version

  for i = 1, #peers do
    local release_version = peers[i].release_version
    if not release_version then
      return nil, "no release_version for peer " .. peers[i].host
    end

    local peer_major_version = tonumber(extract_major(release_version))
    if not peer_major_version then
      return nil, "failed to extract major version for peer " .. peers[i].host
                  .. " with version: " .. tostring(peers[i].release_version)
    end

    if i == 1 then
      major_version = peer_major_version

    elseif peer_major_version ~= major_version then
      return nil, "different major versions detected"
    end
  end

  self.major_version = major_version

  return true
end


function CassandraConnector:connect()
  if self.connection then
    return
  end

  local peer, err = self.cluster:next_coordinator()
  if not peer then
    return nil, err
  end

  self.connection = peer

  return true
end


function CassandraConnector:setkeepalive()
  if not self.connection then
    return
  end

  local ok, err = self.connection:setkeepalive()

  self.connection = nil

  if not ok then
    return nil, err
  end

  return true
end


function CassandraConnector:query(query, args, opts, operation)
  if operation ~= nil and operation ~= "read" and operation ~= "write" then
    error("operation must be 'read' or 'write', was: " .. tostring(operation), 2)
  end

  if not opts then
    opts = {}
  end

  if operation == "write" then
    opts.consistency = self.opts.write_consistency

  else
    opts.consistency = self.opts.read_consistency
  end

  opts.serial_consistency = self.opts.serial_consistency

  local coordinator = self.connection
  if not coordinator then
    local err
    coordinator, err = self.cluster:next_coordinator()
    if not coordinator then
      return nil, err
    end
  end

  -- TODO: prepare queries
  local res, err = coordinator:execute(query, args, opts)

  if not self.connection then
    coordinator:setkeepalive()
  end

  if err then
    return nil, err
  end

  return res
end


local function select_tables(self)
  if not self.major_version then
    return nil, "missing self.major_version"
  end

  local cql

  if self.major_version == 3 then
    cql = [[SELECT * FROM system_schema.tables WHERE keyspace_name = ?]]

  else
    cql = [[SELECT * FROM system.schema_columnfamilies
            WHERE keyspace_name = ?]]
  end

  return self:query(cql, { self.keyspace })
end


function CassandraConnector:reset()
  local ok, err = self:connect()
  if not ok then
    return nil, err
  end

  local rows, err = select_tables(self)
  if not rows then
    return nil, err
  end

  for i = 1, #rows do
    local table_name = self.major_version == 3
                       and rows[i].table_name
                       or rows[i].columnfamily_name

    -- deletes table and indexes
    local cql = string.format("DROP TABLE %s.%s",
                              self.keyspace, table_name)

    local ok, err = self:query(cql)
    if not ok then
      self:setkeepalive()
      return nil, err
    end
  end

  ok, err = self.cluster:wait_schema_consensus(self.connection)
  if not ok then
    return nil, err
  end

  ok, err = self:setkeepalive()
  if not ok then
    return nil, err
  end

  return true
end


function CassandraConnector:truncate()
  local ok, err = self:connect()
  if not ok then
    return nil, err
  end

  local rows, err = select_tables(self)
  if not rows then
    return nil, err
  end

  for i = 1, #rows do
    local table_name = self.major_version == 3
                       and rows[i].table_name
                       or rows[i].columnfamily_name

    if table_name ~= "schema_migrations" then
      local cql = string.format("TRUNCATE TABLE %s.%s",
                                self.keyspace, table_name)

      local ok, err = self:query(cql)
      if not ok then
        self:setkeepalive()
        return nil, err
      end
    end
  end

  ok, err = self:setkeepalive()
  if not ok then
    return nil, err
  end

  return true
end


return CassandraConnector
