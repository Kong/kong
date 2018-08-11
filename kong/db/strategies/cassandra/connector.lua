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

  elseif kong_config.cassandra_lb_policy == "RequestRoundRobin" then
    local policy = require("resty.cassandra.policies.lb.req_rr")
    cluster_options.lb_policy = policy.new()

  elseif kong_config.cassandra_lb_policy == "DCAwareRoundRobin" then
    local policy = require("resty.cassandra.policies.lb.dc_rr")
    cluster_options.lb_policy = policy.new(kong_config.cassandra_local_datacenter)

  elseif kong_config.cassandra_lb_policy == "RequestDCAwareRoundRobin" then
    local policy = require("resty.cassandra.policies.lb.req_dc_rr")
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


-- open a connection from the first available contact point,
-- without a keyspace
function CassandraConnector:connect_migrations(opts)
  if self.connection then
    return
  end

  opts = opts or {}

  local peer, err = self.cluster:first_coordinator()
  if not peer then
    return nil, "failed to acquire contact point: " .. err
  end

  if opts.use_keyspace then
    local ok, err = peer:change_keyspace(self.keyspace)
    if not ok then
      return nil, err
    end
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


function CassandraConnector:close()
  if not self.connection then
    return
  end

  local ok, err = self.connection:close()

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


local function select_keyspaces(self)
  if not self.connection then
    error("no connection")
  end

  if not self.major_version then
    return nil, "missing self.major_version"
  end

  local cql

  if self.major_version == 3 then
    cql = [[SELECT * FROM system_schema.keyspaces
              WHERE keyspace_name = ?]]

  else
    cql = [[SELECT * FROM system.schema_keyspaces
              WHERE keyspace_name = ?]]
  end

  return self.connection:execute(cql, { self.keyspace })
end


local function select_tables(self)
  if not self.connection then
    error("no connection")
  end

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

  return self.connection:execute(cql, { self.keyspace })
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

    if table_name ~= "schema_migrations" and
       table_name ~= "schema_meta" and
       table_name ~= "locks" then
      local cql = string.format("TRUNCATE TABLE %s.%s",
                                self.keyspace, table_name)

      local ok, err = self:query(cql, nil, nil, "write")
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


function CassandraConnector:truncate_table(table_name)
  local cql = string.format("TRUNCATE TABLE %s.%s",
                            self.keyspace, table_name)

  return self:query(cql, nil, nil, "write")
end


function CassandraConnector:setup_locks(default_ttl)
  local ok, err = self:connect()
  if not ok then
    return nil, err
  end

  local cql = string.format([[
    CREATE TABLE IF NOT EXISTS locks(
      key text PRIMARY KEY,
      owner text
    ) WITH default_time_to_live = %d
  ]], default_ttl)

  local ok, err = self:query(cql)
  if not ok then
    self:setkeepalive()
    return nil, err
  end

  ok, err = self.cluster:wait_schema_consensus(self.connection)
  if not ok then
    self:setkeepalive()
    return nil, err
  end

  self:setkeepalive()

  return true
end


function CassandraConnector:insert_lock(key, ttl, owner)
  local cql = string.format([[
    INSERT INTO locks(key, owner)
      VALUES(?, ?)
      IF NOT EXISTS
      USING TTL %d
  ]], ttl)

  local res, err = self:query(cql, { key, owner }, {
    consistency = cassandra.consistencies.quorum,
  })
  if not res then
    return nil, err
  end

  res = res[1]
  if not res then
    return nil, "unexpected result"
  end

  return res["[applied]"]
end


function CassandraConnector:read_lock(key)
  local res, err = self:query([[
    SELECT * FROM locks WHERE key = ?
  ]], { key }, {
    consistency = cassandra.consistencies.serial,
  })
  if not res then
    return nil, err
  end

  return res[1] ~= nil
end


function CassandraConnector:remove_lock(key, owner)
  local res, err = self:query([[
    DELETE FROM locks WHERE key = ? IF owner = ?
  ]], { key, owner }, {
    consistency = cassandra.consistencies.quorum,
  })
  if not res then
    return nil, err
  end

  return true
end


do
  -- migrations
  local pl_stringx = require "pl.stringx"


  local SCHEMA_META_KEY = "schema_meta"


  function CassandraConnector:schema_migrations()
    if not self.connection then
      error("no connection")
    end

    do
      -- has keyspace table?

      local rows, err = select_keyspaces(self)
      if not rows then
        return nil, err
      end

      local has_keyspace

      for _, row in ipairs(rows) do
        if row.keyspace_name == self.keyspace then
          has_keyspace = true
          break
        end
      end

      if not has_keyspace then
        -- no keyspace needs bootstrap
        return nil
      end
    end

    do
      -- has schema_meta table?

      local rows, err = select_tables(self)
      if not rows then
        return nil, err
      end

      local has_schema_meta_table

      for _, row in ipairs(rows) do
        -- Cassandra 3: table_name
        -- Cassadra 2: columnfamily_name
        if row.table_name == "schema_meta"
          or row.columnfamily_name == "schema_meta" then
          has_schema_meta_table = true
          break
        end
      end

      if not has_schema_meta_table then
        -- keyspace, but no schema: needs bootstrap
        return nil
      end
    end

    local ok, err = self.connection:change_keyspace(self.keyspace)
    if not ok then
      return nil, err
    end

    do
      -- has migrations?

      local rows, err = self.connection:execute([[
        SELECT * FROM schema_meta WHERE key = ?
      ]], {
        SCHEMA_META_KEY,
      })
      if not rows then
        return nil, err
      end

      -- no migrations: is bootstrapped but not migrated
      -- migrations: has some migrations
      return rows
    end
  end


  function CassandraConnector:schema_bootstrap(kong_config)
    -- compute keyspace creation CQL

    local cql_replication
    local cass_repl_strategy = kong_config.cassandra_repl_strategy

    if cass_repl_strategy == "SimpleStrategy" then
      cql_replication = string.format([[
        {'class': 'SimpleStrategy', 'replication_factor': %d}
      ]], kong_config.cassandra_repl_factor)

    elseif cass_repl_strategy == "NetworkTopologyStrategy" then
      local dcs = {}

      for _, dc_conf in ipairs(kong_config.cassandra_data_centers) do
        local dc_name, dc_repl = string.match(dc_conf, "([^:]+):(%d+)")
        if dc_name and dc_repl then
          table.insert(dcs, string.format("'%s': %s", dc_name, dc_repl))
        end
      end

      if #dcs < 1 then
        return nil, "invalid cassandra_data_centers configuration"
      end

      cql_replication = string.format([[
        {'class': 'NetworkTopologyStrategy', %s}
      ]], table.concat(dcs, ", "))

    else
      error("unknown replication_strategy: " .. tostring(cass_repl_strategy))
    end

    -- get a contact point connection (no keyspace set)

    if not self.connection then
      error("no connection")
    end

    -- create keyspace if not exists

    local res, err = self.connection:execute(string.format([[
      CREATE KEYSPACE IF NOT EXISTS %q
      WITH REPLICATION = %s
    ]], kong_config.cassandra_keyspace, cql_replication))
    if not res then
      return nil, err
    end

    local ok, err = self.connection:change_keyspace(kong_config.cassandra_keyspace)
    if not ok then
      return nil, err
    end

    -- create schema meta table if not exists

    local res, err = self.connection:execute([[
      CREATE TABLE IF NOT EXISTS schema_meta (
        key             text,
        subsystem       text,
        last_executed   text,
        executed        set<text>,
        pending         set<text>,

        PRIMARY KEY (key, subsystem)
      )
    ]])
    if not res then
      return nil, err
    end

    ok, err = self.cluster:wait_schema_consensus(self.connection)
    if not ok then
      return nil, err
    end

    return true
  end


  function CassandraConnector:schema_reset()
    if not self.connection then
      error("no connection")
    end

    local ok, err = self.connection:execute(string.format([[
      DROP KEYSPACE IF EXISTS %q
    ]], self.keyspace))
    if not ok then
      return nil, err
    end

    ok, err = self.cluster:wait_schema_consensus(self.connection)
    if not ok then
      return nil, err
    end

    return true
  end


  function CassandraConnector:run_up_migration(up_cql)
    if type(up_cql) ~= "string" then
      error("up_cql must be a string", 2)
    end

    if not self.connection then
      error("no connection")
    end

    local t_cql = pl_stringx.split(up_cql, ";")

    for i = 1, #t_cql do
      local cql = pl_stringx.strip(t_cql[i])
      if cql ~= "" then
        local res, err = self.connection:execute(cql)
        if not res then
          return nil, err
        end
      end
    end

    return true
  end


  function CassandraConnector:record_migration(subsystem, name, state)
    if type(subsystem) ~= "string" then
      error("subsystem must be a string", 2)
    end

    if type(name) ~= "string" then
      error("name must be a string", 2)
    end

    if not self.connection then
      error("no connection")
    end

    local cql
    local args

    if state == "executed" then
      cql = [[UPDATE schema_meta
              SET last_executed = ?, executed = executed + ?
              WHERE key = ? AND subsystem = ?]]
      args = {
        name,
        cassandra.set({ name }),
      }

    elseif state == "pending" then
      cql = [[UPDATE schema_meta
              SET pending = pending + ?
              WHERE key = ? AND subsystem = ?]]
      args = {
        cassandra.set({ name }),
      }

    elseif state == "teardown" then
      cql = [[UPDATE schema_meta
              SET pending = pending - ?, executed = executed + ?,
                  last_executed = ?
              WHERE key = ? AND subsystem = ?]]
      args = {
        cassandra.set({ name }),
        cassandra.set({ name }),
        name,
      }

    else
      error("unknown 'state' argument: " .. tostring(state))
    end

    table.insert(args, SCHEMA_META_KEY)
    table.insert(args, subsystem)

    local res, err = self.connection:execute(cql, args)
    if not res then
      return nil, err
    end

    return true
  end
end


return CassandraConnector
