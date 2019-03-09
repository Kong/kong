local log = require "kong.cmd.utils.log"
local cassandra = require "cassandra"
local Cluster   = require "resty.cassandra.cluster"
local pl_stringx = require "pl.stringx"


local CassandraConnector   = {}
CassandraConnector.__index = CassandraConnector


function CassandraConnector.new(kong_config)
  local resolved_contact_points = {}

  do
    -- Resolve contact points before instantiating cluster, since the
    -- driver does not support hostnames in the contact points list.

    -- TODO: this is an ugly hack to force lua sockets on a third party library

    local tcp_old = ngx.socket.tcp
    local udp_old = ngx.socket.udp

    local dns_no_sync_old = kong_config.dns_no_sync

    package.loaded["socket"] = nil
    package.loaded["kong.tools.dns"] = nil
    package.loaded["resty.dns.client"] = nil
    package.loaded["resty.dns.resolver"] = nil

    ngx.socket.tcp = function(...)
      local tcp = require("socket").tcp(...)
      return setmetatable({}, {
        __newindex = function(_, k, v)
          tcp[k] = v
        end,
        __index = function(_, k)
          if type(tcp[k]) == "function" then
            return function(_, ...)
              if k == "send" then
                local value = select(1, ...)
                if type(value) == "table" then
                  return tcp.send(tcp, table.concat(value))
                end

                return tcp.send(tcp, ...)
              end

              return tcp[k](tcp, ...)
            end
          end

          return tcp[k]
        end
      })
    end

    ngx.socket.udp = function(...)
      local udp = require("socket").udp(...)
      return setmetatable({}, {
        __newindex = function(_, k, v)
          udp[k] = v
        end,
        __index = function(_, k)
          if type(udp[k]) == "function" then
            return function(_, ...)
              if k == "send" then
                local value = select(1, ...)
                if type(value) == "table" then
                  return udp.send(udp, table.concat(value))
                end

                return udp.send(udp, ...)
              end

              return udp[k](udp, ...)
            end
          end

          return udp[k]
        end
      })
    end

    local dns_tools = require "kong.tools.dns"

    kong_config.dns_no_sync = true

    local dns = dns_tools(kong_config)

    for i, cp in ipairs(kong_config.cassandra_contact_points) do
      local ip, err = dns.toip(cp)
      if not ip then
        log.error("could not resolve Cassandra contact point '%s': %s",
                  cp, err)

      else
        log.debug("resolved Cassandra contact point '%s' to: %s", cp, ip)
        resolved_contact_points[i] = ip
      end
    end

    kong_config.dns_no_sync = dns_no_sync_old

    package.loaded["resty.dns.resolver"] = nil
    package.loaded["resty.dns.client"] = nil
    package.loaded["kong.tools.dns"] = nil
    package.loaded["socket"] = nil

    ngx.socket.udp = udp_old
    ngx.socket.tcp = tcp_old
  end

  if #resolved_contact_points == 0 then
    return nil, "could not resolve any of the provided Cassandra " ..
                "contact points (cassandra_contact_points = '" ..
                table.concat(kong_config.cassandra_contact_points, ", ") .. "')"
  end

  local cluster_options       = {
    shm                       = "kong_cassandra",
    contact_points            = resolved_contact_points,
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


local function extract_major_minor(release_version)
  return string.match(release_version, "^((%d+)%.%d+)")
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
  local major_minor_version

  for i = 1, #peers do
    local release_version = peers[i].release_version
    if not release_version then
      return nil, "no release_version for peer " .. peers[i].host
    end

    local major_minor, major = extract_major_minor(release_version)
    major = tonumber(major)
    if not major_minor or not major then
      return nil, "failed to extract major version for peer " .. peers[i].host
                  .. " with version: " .. tostring(peers[i].release_version)
    end

    if i == 1 then
      major_version = major
      major_minor_version = major_minor

    elseif major ~= major_version then
      return nil, "different major versions detected"
    end
  end

  self.major_version = major_version
  self.major_minor_version = major_minor_version

  return true
end


function CassandraConnector:infos()
  local db_ver
  if self.major_minor_version then
    db_ver = extract_major_minor(self.major_minor_version)
  end

  return {
    strategy = "Cassandra",
    db_name = self.keyspace,
    db_desc = "keyspace",
    db_ver = db_ver or "unknown",
  }
end


function CassandraConnector:connect()
  local conn = self:get_stored_connection()
  if conn then
    return conn
  end

  local peer, err = self.cluster:next_coordinator()
  if not peer then
    return nil, err
  end

  self:store_connection(peer)

  return peer
end


-- open a connection from the first available contact point,
-- without a keyspace
function CassandraConnector:connect_migrations(opts)
  local conn = self:get_stored_connection()
  if conn then
    return conn
  end

  opts = opts or {}

  local peer, err = self.cluster:first_coordinator()
  if not peer then
    return nil, "failed to acquire contact point: " .. err
  end

  if not opts.no_keyspace then
    local ok, err = peer:change_keyspace(self.keyspace)
    if not ok then
      return nil, err
    end
  end

  self:store_connection(peer)

  return peer
end


function CassandraConnector:setkeepalive()
  local conn = self:get_stored_connection()
  if not conn then
    return true
  end

  local _, err = conn:setkeepalive()

  self:store_connection(nil)

  if err then
    return nil, err
  end

  return true
end


function CassandraConnector:close()
  local conn = self:get_stored_connection()
  if not conn then
    return true
  end

  local _, err = conn:close()

  self:store_connection(nil)

  if err then
    return nil, err
  end

  return true
end


function CassandraConnector:wait_for_schema_consensus()
  local conn = self:get_stored_connection()
  if not conn then
    error("no connection")
  end

  log.verbose("waiting for Cassandra schema consensus (%dms timeout)...",
              self.cluster.max_schema_consensus_wait)

  local ok, err = self.cluster:wait_schema_consensus(conn)

  log.verbose("Cassandra schema consensus: %s",
              ok and "reached" or "not reached")

  if err then
    return nil, "failed to wait for schema consensus: " .. err
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

  local conn = self:get_stored_connection()

  local coordinator = conn

  if not conn then
    local err
    coordinator, err = self.cluster:next_coordinator()
    if not coordinator then
      return nil, err
    end
  end

  local t_cql = pl_stringx.split(query, ";")

  local res, err

  if #t_cql == 1 then
    -- TODO: prepare queries
    res, err = coordinator:execute(query, args, opts)

  else
    for i = 1, #t_cql do
      local cql = pl_stringx.strip(t_cql[i])
      if cql ~= "" then
        res, err = coordinator:execute(cql, nil, opts)
        if not res then
          break
        end
      end
    end
  end

  if not conn then
    coordinator:setkeepalive()
  end

  if err then
    return nil, err
  end

  return res
end

function CassandraConnector:batch(query_args, opts, operation, logged)
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

  opts.logged = logged

  local conn = self:get_stored_connection()

  local coordinator = conn

  if not conn then
    local err
    coordinator, err = self.cluster:next_coordinator()
    if not coordinator then
      return nil, err
    end
  end

  local res, err = coordinator:batch(query_args, opts)

  if not conn then
    coordinator:setkeepalive()
  end

  if err then
    return nil, err
  end

  return res
end


local function select_keyspaces(self)
  local conn = self:get_stored_connection()
  if not conn then
    error("no connection")
  end

  if not self.major_version then
    return nil, "missing self.major_version"
  end

  local cql

  if self.major_version >= 3 then
    cql = [[SELECT * FROM system_schema.keyspaces
              WHERE keyspace_name = ?]]

  else
    cql = [[SELECT * FROM system.schema_keyspaces
              WHERE keyspace_name = ?]]
  end

  return conn:execute(cql, { self.keyspace })
end


local function select_tables(self)
  local conn = self:get_stored_connection()
  if not conn then
    error("no connection")
  end

  if not self.major_version then
    return nil, "missing self.major_version"
  end

  local cql

  -- Assume a release version number of 3 & greater will use the same schema.
  if self.major_version >= 3 then
    cql = [[SELECT * FROM system_schema.tables WHERE keyspace_name = ?]]

  else
    cql = [[SELECT * FROM system.schema_columnfamilies
            WHERE keyspace_name = ?]]
  end

  return conn:execute(cql, { self.keyspace })
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
    -- Assume a release version number of 3 & greater will use the same schema.
    local table_name = self.major_version >= 3
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

  ok, err = self:wait_for_schema_consensus()
  if not ok then
    self:setkeepalive()
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
    -- Assume a release version number of 3 & greater will use the same schema.
    local table_name = self.major_version >= 3
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


function CassandraConnector:setup_locks(default_ttl, no_schema_consensus)
  local ok, err = self:connect()
  if not ok then
    return nil, err
  end

  log.debug("creating 'locks' table if not existing...")

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

  log.debug("successfully created 'locks' table")

  if not no_schema_consensus then
    -- called from tests, ignored when called from bootstrapping, since
    -- we wait for schema consensus as part of bootstrap
    ok, err = self:wait_for_schema_consensus()
    if not ok then
      self:setkeepalive()
      return nil, err
    end

    self:setkeepalive()
  end

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


  local SCHEMA_META_KEY = "schema_meta"


  function CassandraConnector:schema_migrations()
    local conn, err = self:connect()
    if not conn then
      error(err)
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

    local ok, err = conn:change_keyspace(self.keyspace)
    if not ok then
      return nil, err
    end

    do
      -- has migrations?

      local rows, err = conn:execute([[
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


  function CassandraConnector:schema_bootstrap(kong_config, default_locks_ttl)
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

    local conn = self:get_stored_connection()
    if not conn then
      error("no connection")
    end

    -- create keyspace if not exists

    log.debug("creating '%s' keyspace if not existing...",
              kong_config.cassandra_keyspace)

    local res, err = conn:execute(string.format([[
      CREATE KEYSPACE IF NOT EXISTS %q
      WITH REPLICATION = %s
    ]], kong_config.cassandra_keyspace, cql_replication))
    if not res then
      return nil, err
    end

    log.debug("successfully created '%s' keyspace",
              kong_config.cassandra_keyspace)

    local ok, err = conn:change_keyspace(kong_config.cassandra_keyspace)
    if not ok then
      return nil, err
    end

    -- create schema meta table if not exists

    log.debug("creating 'schema_meta' table if not existing...")

    local res, err = conn:execute([[
      CREATE TABLE IF NOT EXISTS schema_meta(
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

    log.debug("successfully created 'schema_meta' table")

    ok, err = self:setup_locks(default_locks_ttl, true) -- no schema consensus
    if not ok then
      return nil, err
    end

    ok, err = self:wait_for_schema_consensus()
    if not ok then
      return nil, err
    end

    return true
  end


  function CassandraConnector:schema_reset()
    local conn = self:get_stored_connection()
    if not conn then
      error("no connection")
    end

    local ok, err = conn:execute(string.format([[
      DROP KEYSPACE IF EXISTS %q
    ]], self.keyspace))
    if not ok then
      return nil, err
    end

    log("dropped '%s' keyspace", self.keyspace)

    ok, err = self:wait_for_schema_consensus()
    if not ok then
      return nil, err
    end

    return true
  end


  function CassandraConnector:run_up_migration(name, up_cql)
    if type(name) ~= "string" then
      error("name must be a string", 2)
    end

    if type(up_cql) ~= "string" then
      error("up_cql must be a string", 2)
    end

    local conn = self:get_stored_connection()
    if not conn then
      error("no connection")
    end

    local t_cql = pl_stringx.split(up_cql, ";")

    for i = 1, #t_cql do
      local cql = pl_stringx.strip(t_cql[i])
      if cql ~= "" then
        local res, err = conn:execute(cql)
        if not res then
          if string.find(err, "Column .- was not found in table")
             or string.find(err, "[Ii]nvalid column name") then
            log.warn("ignored error while running '%s' migration: %s (%s)",
                     name, err, cql:gsub("\n", " "):gsub("%s%s+", " "))

          else
            return nil, err
          end
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

    local conn = self:get_stored_connection()
    if not conn then
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

    local res, err = conn:execute(cql, args)
    if not res then
      return nil, err
    end

    return true
  end


  local function does_table_exist(self, table_name)
    local cql

    -- For now we will assume that a release version number of 3 and greater
    -- will use the same schema. This is recognized as a hotfix and will be
    -- revisited for a more considered solution at a later time.
    if self.major_version >= 3 then
      cql = [[
        SELECT COUNT(*) FROM system_schema.tables
         WHERE keyspace_name = ? AND table_name = ?
      ]]

    else
      cql = [[
        SELECT COUNT(*) FROM system.schema_columnfamilies
         WHERE keyspace_name = ? AND columnfamily_name = ?
      ]]
    end

    local conn = self:get_stored_connection()
    if not conn then
      error("no connection")
    end

    local rows, err = conn:execute(cql, {
      self.keyspace,
      table_name,
    })
    if err then
      return nil, err
    end

    if not rows or not rows[1] or rows[1].count == 0 then
      return false
    end

    return true
  end


  function CassandraConnector:are_014_apis_present()
    local exists, err = does_table_exist(self, "apis")
    if err then
      return nil, err
    end

    if not exists then
      return false
    end

    local rows, err = self:query([[
      SELECT * FROM ]] .. self.keyspace .. [[.apis LIMIT 1;
    ]])
    if err then
      return nil, err
    end
    return rows and #rows > 0 or false
  end


  function CassandraConnector:is_014()
    local res = {}

    local needed_migrations = {
      ["core"] = {
        "2015-01-12-175310_skeleton",
        "2015-01-12-175310_init_schema",
        "2015-11-23-817313_nodes",
        "2016-02-25-160900_remove_null_consumer_id",
        "2016-02-29-121813_remove_ttls",
        "2016-09-05-212515_retries_step_1",
        "2016-09-05-212515_retries_step_2",
        "2016-09-16-141423_upstreams",
        "2016-12-14-172100_move_ssl_certs_to_core",
        "2016-11-11-151900_new_apis_router_1",
        "2016-11-11-151900_new_apis_router_2",
        "2016-11-11-151900_new_apis_router_3",
        "2017-01-24-132600_upstream_timeouts",
        "2017-01-24-132600_upstream_timeouts_2",
        "2017-03-27-132300_anonymous",
        "2017-04-04-145100_cluster_events",
        "2017-05-19-173100_remove_nodes_table",
        "2017-07-28-225000_balancer_orderlist_remove",
        "2017-11-07-192000_upstream_healthchecks",
        "2017-10-27-134100_consistent_hashing_1",
        "2017-11-07-192100_upstream_healthchecks_2",
        "2017-10-27-134100_consistent_hashing_2",
        "2017-09-14-140200_routes_and_services",
        "2017-10-25-180700_plugins_routes_and_services",
        "2018-02-23-142400_targets_add_index",
        "2018-03-22-141700_create_new_ssl_tables",
        "2018-03-26-234600_copy_records_to_new_ssl_tables",
        "2018-03-27-002500_drop_old_ssl_tables",
        "2018-03-16-160000_index_consumers",
        "2018-05-17-173100_hash_on_cookie",
      },
      ["response-transformer"] = {
        "2016-03-10-160000_resp_trans_schema_changes",
      },
      ["jwt"] = {
        "2015-06-09-jwt-auth",
        "2016-03-07-jwt-alg",
        "2017-07-31-120200_jwt-auth_preflight_default",
        "2017-10-25-211200_jwt_cookie_names_default",
        "2018-03-15-150000_jwt_maximum_expiration",
      },
      ["ip-restriction"] = {
        "2016-05-24-remove-cache",
      },
      ["statsd"] = {
        "2017-06-09-160000_statsd_schema_changes",
      },
      ["cors"] = {
        "2017-03-14_multiple_orgins",
      },
      ["basic-auth"] = {
        "2015-08-03-132400_init_basicauth",
      },
      ["key-auth"] = {
        "2015-07-31-172400_init_keyauth",
        "2017-07-31-120200_key-auth_preflight_default",
      },
      ["ldap-auth"] = {
        "2017-10-23-150900_header_type_default",
      },
      ["hmac-auth"] = {
        "2015-09-16-132400_init_hmacauth",
        "2017-06-21-132400_init_hmacauth",
      },
      ["datadog"] = {
        "2017-06-09-160000_datadog_schema_changes",
      },
      ["tcp-log"] = {
        "2017-12-13-120000_tcp-log_tls",
      },
      ["acl"] = {
        "2015-08-25-841841_init_acl",
      },
      ["response-ratelimiting"] = {
        "2015-08-21_init_response-rate-limiting",
        "2016-08-04-321512_response-rate-limiting_policies",
        "2017-12-19-120000_add_route_and_service_id_to_response_ratelimiting",
      },
      ["request-transformer"] = {
        "2016-03-10-160000_req_trans_schema_changes",
      },
      ["rate-limiting"] = {
        "2015-08-03-132400_init_ratelimiting",
        "2016-07-25-471385_ratelimiting_policies",
        "2017-11-30-120000_add_route_and_service_id",
      },
      ["oauth2"] = {
        "2016-09-19-oauth2_api_id",
        "2016-12-15-set_global_credentials",
        "2017-10-19-set_auth_header_name_default",
        "2017-10-11-oauth2_new_refresh_token_ttl_config_value",
        "2018-01-09-oauth2_c_add_service_id",
      },
    }

    local exists, err = does_table_exist(self, "schema_migrations")
    if err then
      return nil, err
    end

    if not exists then
      -- no trace of legacy migrations: above 0.14
      return res
    end

    local conn = self:get_stored_connection()
    if not conn then
      error("no connection")
    end

    local ok, err = conn:change_keyspace(self.keyspace)
    if not ok then
      return nil, err
    end

    local schema_migrations_rows, err = conn:execute([[
      SELECT id, migrations FROM schema_migrations
    ]])
    if err then
      return nil, err
    end

    if not schema_migrations_rows then
      -- empty legacy migrations: invalid state
      res.invalid_state = true
      return res
    end

    local schema_migrations = {}
    for i = 1, #schema_migrations_rows do
      local row = schema_migrations_rows[i]
      schema_migrations[row.id] = row.migrations
    end

    for name, migrations in pairs(needed_migrations) do
      local current_migrations = schema_migrations[name]
      if not current_migrations then
        -- missing all migrations for a component: below 0.14
        res.invalid_state = true
        res.missing_component = name
        return res
      end

      for _, needed_migration in ipairs(migrations) do
        local found = false
        for _, current_migration in ipairs(current_migrations) do
          if current_migration == needed_migration then
            found = true
            break
          end
        end

        if not found then
          -- missing at least one migration for a component: below 0.14
          res.invalid_state = true
          res.missing_component = name
          res.missing_migration = needed_migration
          return res
        end
      end
    end

    -- all migrations match: 0.14 install
    res.is_014 = true

    return res
  end
end


return CassandraConnector
