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
    --
    -- The below logic includes a hack so that we are able to run our DNS
    -- resolver in init_by_lua:
    --
    -- 1. We override ngx.socket.tcp/udp so that resty.dns.resolver will run
    --    in init_by_lua (which has no cosockets)
    -- 2. We force the dns_no_sync option so that resty.dns.client will not
    --    spawn an ngx.timer (not supported in init_by_lua)
    --
    -- TODO: replace fallback logic with lua-resty-socket once it supports
    --       ngx.socket.udp

    local tcp_old = ngx.socket.tcp
    local udp_old = ngx.socket.udp

    local dns_no_sync_old = kong_config.dns_no_sync

    package.loaded["socket"] = nil
    package.loaded["kong.tools.dns"] = nil
    package.loaded["resty.dns.client"] = nil
    package.loaded["resty.dns.resolver"] = nil

    ngx.socket.tcp = function(...) -- luacheck: ignore
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

    ngx.socket.udp = function(...) -- luacheck: ignore
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
      local ip, err, try_list = dns.toip(cp)
      if not ip then
        log.error("[cassandra] DNS resolution failed for contact " ..
                  "point '%s': %s. Tried: %s", cp, err, tostring(try_list))

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

    ngx.socket.udp = udp_old -- luacheck: ignore
    ngx.socket.tcp = tcp_old -- luacheck: ignore
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

  local serial_consistency

  if string.find(kong_config.cassandra_lb_policy, "DCAware", nil, true) then
    serial_consistency = cassandra.consistencies.local_serial

  else
    serial_consistency = cassandra.consistencies.serial
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
      serial_consistency = serial_consistency,
    },
    refresh_frequency = kong_config.cassandra_refresh_frequency,
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


function CassandraConnector:init_worker()
  if self.refresh_frequency > 0 then
    local hdl, err = ngx.timer.every(self.refresh_frequency, function()
      local ok, err, topology = self.cluster:refresh(self.refresh_frequency)
      if not ok then
        ngx.log(ngx.ERR, "[cassandra] failed to refresh cluster topology: ",
                         err)

      elseif topology then
        if #topology.added > 0 then
          ngx.log(ngx.NOTICE, "[cassandra] peers added to cluster topology: ",
                              table.concat(topology.added, ", "))
        end

        if #topology.removed > 0 then
          ngx.log(ngx.NOTICE, "[cassandra] peers removed from cluster topology: ",
                              table.concat(topology.removed, ", "))
        end
      end
    end)
    if not hdl then
      return nil, "failed to initialize Cassandra topology refresh timer: " ..
                  err
    end
  end

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

    local keyspace = kong_config.cassandra_keyspace
    local ok = conn:change_keyspace(keyspace)
    if not ok then
      log.debug("creating '%s' keyspace if not existing...", keyspace)

      local res, err = conn:execute(string.format([[
        CREATE KEYSPACE IF NOT EXISTS %q
        WITH REPLICATION = %s
      ]], keyspace, cql_replication))
      if not res then
        return nil, err
      end

      log.debug("successfully created '%s' keyspace", keyspace)
    end

    local ok, err = conn:change_keyspace(keyspace)
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


  function CassandraConnector:run_api_migrations(opts)
    local conn = self:get_stored_connection()
    if not conn then
      error("no connection")
    end

    local migrated, skipped, failed = 0, 0, 0

    local results = {
      migrated = {},
      skipped  = {},
      failed   = {},
    }

    local constants = require "kong.constants"
    local null = ngx.null

    local apis = { n = 0 }
    for rows, err in self.cluster:iterate([[
    SELECT id,
           created_at,
           name,
           upstream_url,
           preserve_host,
           retries,
           https_only,
           http_if_terminated,
           hosts,
           uris,
           methods,
           strip_uri,
           upstream_connect_timeout,
           upstream_send_timeout,
           upstream_read_timeout
      FROM apis]]) do
      if not rows then
        return nil, err
      end

      for i = 1, #rows do
        local api = rows[i]
        if api.created_at and api.created_at ~= null then
          api.created_at = math.floor(api.created_at / 1000)
        end

        apis.n = apis.n + 1
        apis[apis.n] = api
      end
    end

    if apis.n == 0 then
      return results
    end

    table.sort(apis, function(api_a, api_b)
      return api_a.created_at < api_b.created_at
    end)

    local plugins = {}
    for rows, err in self.cluster:iterate([[
    SELECT id,
           name,
           api_id
      FROM plugins]]) do
      if not rows then
        return nil, err
      end

      for i = 1, #rows do
        local plugin = rows[i]
        local api_id = plugin.api_id
        if api_id ~= nil and
           api_id ~= null then
          if not plugins[api_id] then
            plugins[api_id] = { n = 0 }
          end

          plugins[api_id].n = plugins[api_id].n + 1
          plugins[api_id][plugins[api_id].n] = plugin
        end
      end
    end

    local cjson = require "cjson.safe"
    local utils = require "kong.tools.utils"
    local url   = require "socket.url"

    local migrations = { n = apis.n }
    for i = 1, apis.n do
      local api = apis[i]

      local created_at
      local updated_at
      if api.created_at ~= nil and
         api.created_at ~= null then
        created_at = math.floor(api.created_at)
        updated_at = created_at
      else
        created_at = ngx.time()
        updated_at = created_at
      end

      local protocol
      local host
      local port
      local path
      if api.upstream_url ~= nil and
         api.upstream_url ~= null then
        local parsed_url = url.parse(api.upstream_url)

        if parsed_url.scheme then
          protocol = parsed_url.scheme
        end

        if parsed_url.host then
          host = parsed_url.host
        end

        if parsed_url.port then
          port = tonumber(parsed_url.port, 10)
        end

        if not port and protocol then
          if protocol == "http" then
            port = 80
          elseif protocol == "https" then
            port = 443
          end
        end

        if parsed_url.path then
          path = parsed_url.path
        end
      end

      local name
      if api.name ~= nil and
         api.name ~= null then
        name = api.name
      end

      local retries
      local connect_timeout
      local write_timeout
      local read_timeout

      if api.retries ~= nil and
         api.retries ~= null then
        retries = tonumber(api.retries, 10)
      end

      if api.upstream_connect_timeout ~= nil and
         api.upstream_connect_timeout ~= null then
        connect_timeout = tonumber(api.upstream_connect_timeout, 10)
      end

      if api.upstream_send_timeout ~= nil and
         api.upstream_send_timeout ~= null then
        write_timeout = tonumber(api.upstream_send_timeout, 10)
      end

      if api.upstream_read_timeout ~= nil and
         api.upstream_read_timeout ~= null then
        read_timeout = tonumber(api.upstream_read_timeout, 10)
      end

      local service_id = utils.uuid()
      local service = {
        id              = service_id,
        name            = name,
        created_at      = created_at,
        updated_at      = updated_at,
        retries         = retries,
        protocol        = protocol,
        host            = host,
        port            = port,
        path            = path,
        connect_timeout = connect_timeout,
        write_timeout   = write_timeout,
        read_timeout    = read_timeout,
      }

      local route_id = utils.uuid()

      local methods
      if api.methods ~= nil and
         api.methods ~= null then
        methods = cjson.decode(api.methods)
      end

      local hosts
      if api.hosts ~= nil and
         api.hosts ~= null then
        hosts = cjson.decode(api.hosts)
      end

      local paths
      if api.uris ~= nil and
         api.uris ~= null then
        paths = cjson.decode(api.uris)
      end

      local regex_priority = 0

      local strip_path
      local preserve_host
      local https_only

      if api.strip_uri ~= nil and
         api.strip_uri ~= null then
        strip_path = not not api.strip_uri
      end

      if api.preserve_host ~= nil and
         api.preserve_host ~= null then
        preserve_host = not not api.preserve_host
      end

      if api.https_only ~= nil and
         api.https_only ~= null then
        https_only = not not api.https_only
      end

      local protocols = https_only and { "https" } or { "http", "https" }

      local route = {
        id             = route_id,
        created_at     = created_at,
        updated_at     = updated_at,
        service_id     = service_id,
        protocols      = protocols,
        methods        = methods,
        hosts          = hosts,
        paths          = paths,
        regex_priority = regex_priority,
        strip_path     = strip_path,
        preserve_host  = preserve_host,
        path_handling  = "v0",
      }

      migrations[i] = {
        api     = api,
        route   = route,
        service = service,
        plugins = plugins[api.id]
      }
    end

    local escape = function(literal, type)
      if literal == nil or literal == null then
        return cassandra.null
      end

      if type == "string" then
        return cassandra.text(literal)
      end

      if type == "boolean" then
        return cassandra.boolean(literal)
      end

      if type == "integer" then
        return cassandra.int(literal)
      end

      if type == "timestamp" then
        return cassandra.timestamp(literal * 1000)
      end

      if type == "uuid" then
        return cassandra.uuid(literal)
      end

      if type == "array" then
        local t = {}

        for i = 1, #literal do
          if literal[i] == nil or literal[i] == null then
            t[i] = cassandra.null
          else
            t[i] = cassandra.text(literal[i])
          end
        end

        return cassandra.list(t)
      end

      return self:escape_literal(literal)
    end

    local force
    if opts then
      force = not not opts.force
    end

    for i = 1, migrations.n do
      local migration = migrations[i]
      local service   = migration.service
      local route     = migration.route
      local api       = migration.api
      local api_name  = api.name or api.id

      local custom_plugins_count = 0
      local custom_plugins = {}

      local queries = 3

      local cql = { { [[
  INSERT INTO services (partition, id, created_at, updated_at, name, retries, protocol, host, port, path, connect_timeout, write_timeout, read_timeout)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]], {
            escape("services", "string"),
            escape(service.id, "uuid"),
            escape(service.created_at, "timestamp"),
            escape(service.updated_at, "timestamp"),
            escape(service.name, "string"),
            escape(service.retries, "integer"),
            escape(service.protocol, "string"),
            escape(service.host, "string"),
            escape(service.port, "integer"),
            escape(service.path, "string"),
            escape(service.connect_timeout, "integer"),
            escape(service.write_timeout, "integer"),
            escape(service.read_timeout, "integer"),
          },
        }, { [[
  INSERT INTO routes (partition, id, created_at, updated_at, service_id, protocols, methods, hosts, paths, regex_priority, strip_path, preserve_host, path_handling)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]], {
            escape("routes", "string"),
            escape(route.id, "uuid"),
            escape(route.created_at, "timestamp"),
            escape(route.updated_at, "timestamp"),
            escape(route.service_id, "uuid"),
            escape(route.protocols, "array"),
            escape(route.methods, "array"),
            escape(route.hosts, "array"),
            escape(route.paths, "array"),
            escape(route.regex_priority, "integer"),
            escape(route.strip_path, "boolean"),
            escape(route.preserve_host, "boolean"),
            escape(route.path_handling, "string"),
          },
        },
      }

      if migration.plugins then
        queries = queries + migration.plugins.n
        for j = 1, migration.plugins.n do
          local plugin = migration.plugins[j]
          if not constants.BUNDLED_PLUGINS[plugin.name] then
            custom_plugins_count = custom_plugins_count + 1
            custom_plugins[custom_plugins_count] = true
          end

          -- just future proofing
          if plugin.name ~= nil and
             plugin.name ~= null then
            cql[j + 2] = { [[
       UPDATE plugins
          SET route_id = ?, api_id = ?
        WHERE id   = ?
          AND name = ?]], {
                escape(route.id, "uuid"),
                escape(nil),
                escape(plugin.id, "uuid"),
                escape(plugin.name, "string"),
              },
            }
          else
            cql[j + 2] = { [[
       UPDATE plugins
          SET route_id = ?, api_id = ?
        WHERE id = ?]], {
                escape(route.id, "uuid"),
                escape(nil),
                escape(plugin.id, "uuid"),
              },
            }
          end
        end
      end

      cql[queries] = { [[
  DELETE FROM apis
        WHERE id = ?]], {
          escape(api.id, "uuid")
        },
      }

      log("migrating api '%s' ...", api_name)
      --log.debug(cql)

      if not force and custom_plugins_count > 0 then
        log("migrating api '%s' skipped (use -f to migrate apis with " ..
            "custom plugins", api_name)
        skipped = skipped + 1
        results.skipped[skipped] = {
          api = api,
          custom_plugins = custom_plugins,
        }

      else
        local res, err = self:batch(cql, nil, "write", true)
        if not res then
          log("migrating api '%s' failed (%s)", api_name, err)
          failed = failed + 1
          results.failed[failed] = {
            api = api,
            err = err,
          }

        else
          log("migrating api '%s' done", api_name)
          migrated = migrated + 1
          results.migrated[migrated] = {
            api = api,
          }
        end
      end
    end

    if migrated > 0 then
      log("%d/%d migrations succeeded", migrated, migrations.n)
    end

    if skipped > 0 then
      log("%d/%d migrations skipped", skipped, migrations.n)
    end

    if failed > 0 then
      log("%d/%d migrations failed", skipped, migrations.n)
    end

    return results
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
          or string.find(err, "[Ii]nvalid column name")
          or string.find(err, "[Uu]ndefined column name")
          or string.find(err, "No column definition found for column")
          or string.find(err, "Undefined name .- in selection clause")
          then
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
end


return CassandraConnector
