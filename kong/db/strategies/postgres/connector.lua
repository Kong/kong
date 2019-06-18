local logger       = require "kong.cmd.utils.log"
local pgmoon       = require "pgmoon"
local arrays       = require "pgmoon.arrays"
local stringx      = require "pl.stringx"
local split_prefix   = require "kong.workspaces".split_prefix


local setmetatable = setmetatable
local encode_array = arrays.encode_array
local tonumber     = tonumber
local tostring     = tostring
local concat       = table.concat
local insert       = table.insert
local ipairs       = ipairs
local pairs        = pairs
local error        = error
local floor        = math.floor
local type         = type
local ngx          = ngx
local timer_every  = ngx.timer.every
local update_time  = ngx.update_time
local get_phase    = ngx.get_phase
local null         = ngx.null
local now          = ngx.now
local log          = ngx.log
local match        = string.match
local fmt          = string.format
local sub          = string.sub


local WARN                          = ngx.WARN
local SQL_INFORMATION_SCHEMA_TABLES = [[
SELECT table_name
  FROM information_schema.tables
 WHERE table_schema = CURRENT_SCHEMA;
]]
local PROTECTED_TABLES = {
  schema_migrations = true,
  schema_meta       = true,
  locks             = true,
}


local function now_updated()
  update_time()
  return now()
end



local function visit(k, n, m, s)
  if m[k] == 0 then return 1 end
  if m[k] == 1 then return end
  m[k] = 0
  local f = n[k]
  for i=1, #f do
    if visit(f[i], n, m, s) then return 1 end
  end
  m[k] = 1
  s[#s+1] = k
end


local tsort = {}
tsort.__index = tsort


function tsort.new()
  return setmetatable({ n = {} }, tsort)
end


function tsort:add(...)
  local p = { ... }
  local c = #p
  if c == 0 then return self end
  if c == 1 then
    p = p[1]
    if type(p) == "table" then
      c = #p
    else
      p = { p }
    end
  end
  local n = self.n
  for i=1, c do
    local f = p[i]
    if n[f] == nil then n[f] = {} end
  end
  for i=2, c, 1 do
    local f = p[i]
    local t = p[i-1]
    local o = n[f]
    o[#o+1] = t
  end
  return self
end


function tsort:sort()
  local n  = self.n
  local s = {}
  local m  = {}
  for k in pairs(n) do
    if m[k] == nil then
      if visit(k, n, m, s) then
        return nil, "There is a circular dependency in the graph. It is not possible to derive a topological sort."
      end
    end
  end
  return s
end


local function iterator(rows)
  local i = 0
  return function()
    i = i + 1
    return rows[i]
  end
end


local setkeepalive


local function connect(config)
  local phase  = get_phase()
  -- TODO: remove preread from here when the issue with starttls has been fixed
  -- TODO: make also sure that Cassandra doesn't use LuaSockets on preread after
  --       starttls has been fixed
  if phase == "preread" or phase == "init" or phase == "init_worker" or ngx.IS_CLI then
    -- Force LuaSocket usage in the CLI in order to allow for self-signed
    -- certificates to be trusted (via opts.cafile) in the resty-cli
    -- interpreter (no way to set lua_ssl_trusted_certificate).
    config.socket_type = "luasocket"

  else
    config.socket_type = "nginx"
  end

  local connection = pgmoon.new(config)

  connection.convert_null = true
  connection.NULL         = null

  if config.timeout then
    connection:settimeout(config.timeout)
  end

  local ok, err = connection:connect()
  if not ok then
    return nil, err
  end

  if connection.sock:getreusedtimes() == 0 then
    if config.schema == "" then
      local res = connection:query("SELECT CURRENT_SCHEMA AS schema")
      if res and res[1] and res[1].schema and res[1].schema ~= null then
        config.schema = res[1].schema
      else
        config.schema = "public"
      end
    end

    ok, err = connection:query(concat {
      "SET SCHEMA ",    connection:escape_literal(config.schema), ";\n",
      "SET TIME ZONE ", connection:escape_literal("UTC"), ";",
    })
    if not ok then
      setkeepalive(connection)
      return nil, err
    end
  end

  return connection
end


setkeepalive = function(connection)
  if not connection or not connection.sock then
    return true
  end

  if connection.sock_type == "luasocket" then
    local _, err = connection:disconnect()
    if err then
      return nil, err
    end

  else
    local _, err = connection:keepalive()
    if err then
      return nil, err
    end
  end

  return true
end


local _mt = {}


_mt.__index = _mt


function _mt:get_stored_connection()
  local conn = self.super.get_stored_connection(self)
  if conn and conn.sock then
    return conn
  end
end


function _mt:init()
  local res, err = self:query("SHOW server_version_num;")
  local ver = tonumber(res and res[1] and res[1].server_version_num)
  if not ver then
    return nil, "failed to retrieve server_version_num: " .. err
  end

  local major = floor(ver / 10000)
  if major < 10 then
    self.major_version       = tonumber(fmt("%u.%u", major, floor(ver / 100 % 100)))
    self.major_minor_version = fmt("%u.%u.%u", major, floor(ver / 100 % 100), ver % 100)

  else
    self.major_version       = major
    self.major_minor_version = fmt("%u.%u", major, ver % 100)
  end

  return true
end


function _mt:init_worker(strategies)
  if ngx.worker.id() == 0 then
    local graph
    local found = false

    for _, strategy in pairs(strategies) do
      local schema = strategy.schema
      if schema.ttl then
        if not found then
          graph = tsort.new()
          found = true
        end

        local name = schema.name
        graph:add(name)
        for _, field in schema:each_field() do
          if field.type == "foreign" and field.schema.ttl then
            graph:add(name, field.schema.name)
          end
        end
      end
    end

    if not found then
      return true
    end

    local sorted_strategies = graph:sort()
    local ttl_escaped = self:escape_identifier("ttl")
    local cleanup_statement = {}
    for i, table_name in ipairs(sorted_strategies) do
      cleanup_statement[i] = concat {
        "  DELETE FROM ",
        self:escape_identifier(table_name),
        " WHERE ",
        ttl_escaped,
        " < CURRENT_TIMESTAMP AT TIME ZONE 'UTC';"
      }
    end

    cleanup_statement = concat({
      "BEGIN;",
      concat(cleanup_statement, "\n"),
      "COMMIT;"
    }, "\n")

    return timer_every(60, function(premature)
      if premature then
        return
      end

      local ok, err = self:query(cleanup_statement)
      if not ok then
        if err then
          log(WARN, "unable to clean expired rows from postgres database (", err, ")")
        else
          log(WARN, "unable to clean expired rows from postgres database")
        end
      end
    end)
  end

  return true
end


function _mt:infos()
  local db_ver
  if self.major_minor_version then
    db_ver = match(self.major_minor_version, "^(%d+%.%d+)")
  end

  return {
    strategy = "PostgreSQL",
    db_name  = self.config.database,
    db_desc  = "database",
    db_ver   = db_ver or "unknown",
  }
end


function _mt:connect()
  local conn = self:get_stored_connection()
  if conn then
    return conn
  end

  local connection, err = connect(self.config)
  if not connection then
    return nil, err
  end

  self:store_connection(connection)

  return connection
end


function _mt:connect_migrations()
  return self:connect()
end


function _mt:close()
  local conn = self:get_stored_connection()
  if not conn then
    return true
  end

  local _, err = conn:disconnect()

  self:store_connection(nil)

  if err then
    return nil, err
  end

  return true
end


function _mt:setkeepalive()
  local conn = self:get_stored_connection()
  if not conn then
    return true
  end

  local _, err = setkeepalive(conn)

  self:store_connection(nil)

  if err then
    return nil, err
  end

  return true
end


function _mt:query(sql)
  local res, err, partial, num_queries

  local conn = self:get_stored_connection()
  if conn then
    res, err, partial, num_queries = conn:query(sql)

  else
    local connection
    connection, err = connect(self.config)
    if not connection then
      return nil, err
    end

    res, err, partial, num_queries = connection:query(sql)

    setkeepalive(connection)
  end

  if res then
    return res, nil, partial, num_queries or err
  end

  return nil, err, partial, num_queries
end


function _mt:iterate(sql)
  local res, err, partial, num_queries = self:query(sql)
  if not res then
    local failed = false
    return function()
      if not failed then
        failed = true
        return false, err, partial, num_queries
      end
      -- return error only once to avoid infinite loop
      return nil
    end
  end

  if res == true then
    return iterator { true }
  end

  return iterator(res)
end


function _mt:reset()
  local schema = self:escape_identifier(self.config.schema)
  local user = self:escape_identifier(self.config.user)

  local ok, err = self:query(concat {
    "BEGIN;\n",
    "  DROP SCHEMA IF EXISTS ", schema ," CASCADE;\n",
    "  CREATE SCHEMA IF NOT EXISTS ", schema, " AUTHORIZATION ", user, ";\n",
    "  GRANT ALL ON SCHEMA ", schema ," TO ", user, ";\n",
    "COMMIT;",
  })

  if not ok then
    return nil, err
  end

  return true
end


function _mt:truncate()
  local i, table_names = 0, {}

  for row in self:iterate(SQL_INFORMATION_SCHEMA_TABLES) do
    local table_name = row.table_name
    if not PROTECTED_TABLES[table_name] then
      i = i + 1
      table_names[i] = self:escape_identifier(table_name)
    end
  end

  if i == 0 then
    return true
  end

  local truncate_statement = concat {
    "TRUNCATE ", concat(table_names, ", "), " RESTART IDENTITY CASCADE;"
  }

  local ok, err = self:query(truncate_statement)
  if not ok then
    return nil, err
  end

  return true
end


function _mt:truncate_table(table_name)
  local truncate_statement = concat {
    "TRUNCATE ", self:escape_identifier(table_name), " RESTART IDENTITY CASCADE;"
  }

  local ok, err = self:query(truncate_statement)
  if not ok then
    return nil, err
  end

  return true
end


function _mt:setup_locks(_, _)
  logger.verbose("creating 'locks' table if not existing...")

  local ok, err = self:query([[
BEGIN;
  CREATE TABLE IF NOT EXISTS locks (
    key    TEXT PRIMARY KEY,
    owner  TEXT,
    ttl    TIMESTAMP WITH TIME ZONE
  );
  CREATE INDEX IF NOT EXISTS locks_ttl_idx ON locks (ttl);
COMMIT;]])

  if not ok then
    return nil, err
  end

  logger.verbose("successfully created 'locks' table")

  return true
end


function _mt:insert_lock(key, ttl, owner)
  local ttl_escaped = concat {
                        "TO_TIMESTAMP(",
                        self:escape_literal(tonumber(fmt("%.3f", now_updated() + ttl))),
                        ") AT TIME ZONE 'UTC'"
                      }

  local sql = concat { "BEGIN;\n",
                       "  DELETE FROM locks\n",
                       "        WHERE ttl < CURRENT_TIMESTAMP AT TIME ZONE 'UTC';\n",
                       "  INSERT INTO locks (key, owner, ttl)\n",
                       "       VALUES (", self:escape_literal(key),   ", ",
                                          self:escape_literal(owner), ", ",
                                          ttl_escaped, ")\n",
                       "  ON CONFLICT DO NOTHING;\n",
                       "COMMIT;"
  }

  local res, err, _, num_queries = self:query(sql)
  if not res then
    return nil, err
  end

  if num_queries ~= 4 then
    return nil, "unexpected result"
  end

  if res[3] and res[3].affected_rows == 1 then
    return true
  end

  return false
end


function _mt:read_lock(key)
  local sql = concat {
    "SELECT *\n",
    "  FROM locks\n",
    " WHERE key = ", self:escape_literal(key), "\n",
    "   AND ttl >= CURRENT_TIMESTAMP AT TIME ZONE 'UTC'\n",
    " LIMIT 1;"
  }

  local res, err = self:query(sql)
  if not res then
    return nil, err
  end

  return res[1] ~= nil
end


function _mt:remove_lock(key, owner)
  local sql = concat {
    "DELETE FROM locks\n",
    "      WHERE key   = ", self:escape_literal(key), "\n",
         "   AND owner = ", self:escape_literal(owner), ";"
  }

  local res, err = self:query(sql)
  if not res then
    return nil, err
  end

  return true
end


function _mt:schema_migrations()
  local conn = self:get_stored_connection()
  if not conn then
    error("no connection")
  end

  local has_schema_meta_table
  for row in self:iterate(SQL_INFORMATION_SCHEMA_TABLES) do
    local table_name = row.table_name
    if table_name == "schema_meta" then
      has_schema_meta_table = true
      break
    end
  end

  if not has_schema_meta_table then
    -- database, but no schema_meta: needs bootstrap
    return nil
  end

  local rows, err = self:query(concat({
    "SELECT *\n",
    "  FROM schema_meta\n",
    " WHERE key = ",  self:escape_literal("schema_meta"), ";"
  }))

  if not rows then
    return nil, err
  end

  for _, row in ipairs(rows) do
    if row.pending == null then
      row.pending = nil
    end
  end

  -- no migrations: is bootstrapped but not migrated
  -- migrations: has some migrations
  return rows
end


function _mt:schema_bootstrap(kong_config, default_locks_ttl)
  local conn = self:get_stored_connection()
  if not conn then
    error("no connection")
  end

  -- create schema meta table if not exists

  logger.verbose("creating 'schema_meta' table if not existing...")

  local res, err = self:query([[
    CREATE TABLE IF NOT EXISTS schema_meta (
      key            TEXT,
      subsystem      TEXT,
      last_executed  TEXT,
      executed       TEXT[],
      pending        TEXT[],

      PRIMARY KEY (key, subsystem)
    );]])

  if not res then
    return nil, err
  end

  logger.verbose("successfully created 'schema_meta' table")

  local ok
  ok, err = self:setup_locks(default_locks_ttl, true)
  if not ok then
    return nil, err
  end

  return true
end


function _mt:schema_reset()
  local conn = self:get_stored_connection()
  if not conn then
    error("no connection")
  end

  local schema = self:escape_identifier(self.config.schema)
  local user = self:escape_identifier(self.config.user)

  local ok, err = self:query(concat {
    "BEGIN;\n",
    "  DROP SCHEMA IF EXISTS ", schema, " CASCADE;\n",
    "  CREATE SCHEMA IF NOT EXISTS ", schema, " AUTHORIZATION ", user, ";\n",
    "  GRANT ALL ON SCHEMA ", schema ," TO ", user, ";\n",
    "COMMIT;",
  })

  if not ok then
    return nil, err
  end

  return true
end

function _mt:run_api_migrations(opts)
  local conn = self:get_stored_connection()
  if not conn then
    error("no connection")
  end

  local migrated, skipped, failed = 0, 0, 0

  local results = {
    migrated = {},
    skipped  = {},
    failed   = {},
    script   = nil,
  }

  local apis = { n = 0 }
  for api, err in self:iterate([[
    SELECT id,
           EXTRACT(EPOCH FROM created_at AT TIME ZONE 'UTC') AS created_at,
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
      FROM apis;]]) do
    if not api then
      return nil, err
    end

    apis.n = apis.n + 1
    apis[apis.n] = api
  end

  if apis.n == 0 then
    return results
  end

  table.sort(apis, function(api_a, api_b)
    return api_a.created_at < api_b.created_at
  end)

  local plugins = {}
  for plugin, err in self:iterate([[
    SELECT id,
           name,
           api_id
      FROM plugins;]]) do
    if not plugin then
      return nil, err
    end

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

  local constants = require "kong.constants"
  local cjson     = require "cjson.safe"
  local utils     = require "kong.tools.utils"
  local url       = require "socket.url"

  local migrations = { n = apis.n }
  for i = 1, apis.n do
    local api = apis[i]

    local rbac_role_entities, err = self:query(fmt(
      [[ SELECT
         role_id,
         entity_id,
         entity_type,
         actions,
         negative,
         comment,
         EXTRACT(EPOCH FROM created_at AT TIME ZONE 'UTC') AS created_at
      FROM rbac_role_entities
      WHERE entity_id = '%s';]], api.id)
    )
    if err then
      return nil, err
    end

    local workspace_entities, err = self:query(fmt(concat({
      "SELECT *\n",
      "  FROM workspace_entities \n",
      " WHERE unique_field_name = 'id' and entity_id = '%s';"}), api.id)
    )
    if err then
      return nil, err
    end


    local created_at
    local updated_at
    if api.created_at ~= nil and
       api.created_at ~= null then
      created_at = floor(api.created_at)
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
    }

    migrations[i] = {
      api     = api,
      route   = route,
      service = service,
      plugins = plugins[api.id],
      role_entities   = rbac_role_entities,
      workspace_entities = workspace_entities
    }
  end

  local escape = function(literal, type)
    if literal == nil or
       literal == null then
      return "NULL"
    end

    if type == "timestamp" then
      return concat {
        "TO_TIMESTAMP(", self:escape_literal(tonumber(fmt("%.3f", literal))),
        ") AT TIME ZONE 'UTC'"
      }
    end

    if type == "array" then
      if not literal[1] then
        return self:escape_literal("{}")
      end

      return encode_array(literal)
    end

    return self:escape_literal(literal)
  end

  local force
  if opts then
    force = not not opts.force
  end

  local migration_script = {}

  for i = 1, migrations.n do
    local migration = migrations[i]
    local service   = migration.service
    local route     = migration.route
    local api       = migration.api

    local workspace, api_name  = split_prefix(api.name)
    if not workspace then
      error("no workspace attached")
    end

    local custom_plugins_count = 0
    local custom_plugins = {}

    local plugins_sql = {}
    if migration.plugins then
      for j = 1, migration.plugins.n do
        local plugin = migration.plugins[j]
        if not constants.BUNDLED_PLUGINS[plugin.name] then
          custom_plugins_count = custom_plugins_count + 1
          custom_plugins[custom_plugins_count] = true
        end

        if plugin.name ~= nil and
          plugin.name ~= null then
          plugins_sql[j] = fmt([[

       UPDATE plugins
          SET route_id = %s, api_id = %s
        WHERE id   = %s
          AND name = %s;
]],
          escape(route.id),
          escape(nil),
          escape(plugin.id),
          escape(plugin.name))
        else
          plugins_sql[j] = fmt([[

       UPDATE plugins
          SET route_id = %s, api_id = %s
        WHERE id   = %s;
]],
          escape(route.id),
          escape(nil),
          escape(plugin.id))
        end
      end
    end

    local workspace_sql = {}
    if migration.workspace_entities then
      for _, workspace in ipairs(migration.workspace_entities) do
        insert(workspace_sql, fmt("insert into workspace_entities" ..
          "(workspace_name, workspace_id, entity_id, entity_type, unique_field_name, unique_field_value)" ..
          " values(%s, %s, %s, 'services', 'name', %s);",
          escape(workspace.workspace_name),
          escape(workspace.workspace_id),
          escape(service.id),
          escape(service.name)))

        insert(workspace_sql, fmt("insert into workspace_entities " ..
          "(workspace_name, workspace_id, entity_id, entity_type, unique_field_name, unique_field_value)" ..
          " values(%s, %s, %s, 'services', 'id', %s);",
          escape(workspace.workspace_name),
          escape(workspace.workspace_id),
          escape(service.id),
          escape(service.id)))

        insert(workspace_sql, fmt("insert into workspace_entities " ..
          "(workspace_name, workspace_id, entity_id, entity_type, unique_field_name, unique_field_value)" ..
          " values(%s, %s, %s, 'routes', 'id', %s);",
          escape(workspace.workspace_name),
          escape(workspace.workspace_id),
          escape(route.id),
          escape(route.id)))

        insert(workspace_sql, fmt("DELETE from workspace_entities " ..
          "where workspace_id = %s AND entity_id = %s AND unique_field_name = 'id';",
          escape(workspace.workspace_id),
          escape(api.id)))
      end
    end

    local rbac_roles_sql = {}
    if migration.role_entities then
      for _, row in ipairs(migration.role_entities) do
        local created_at
        if row.created_at ~= nil and
          row.created_at ~= null then
          created_at = floor(row.created_at)
        else
          created_at = ngx.time()
        end

        local rbac_roles_service_sql =
        fmt([[ INSERT INTO rbac_role_entities (role_id, entity_id, entity_type, actions, negative, comment, created_at) VALUES (%s, %s, 'services', %s, %s, %s, %s); ]],
          escape(row.role_id),
          escape(service.id),
          escape(row.actions),
          escape(row.negative),
          escape(row.comment),
          escape(created_at, "timestamp"))
        insert(rbac_roles_sql, rbac_roles_service_sql)
        local rbac_roles_route_sql =
          fmt([[ INSERT INTO rbac_role_entities (role_id, entity_id, entity_type, actions, negative, comment, created_at) VALUES (%s, %s, 'routes', %s, %s, %s, %s); ]],
            escape(row.role_id),
            escape(route.id),
            escape(row.actions),
            escape(row.negative),
            escape(row.comment),
            escape(created_at, "timestamp"))
        insert(rbac_roles_sql, rbac_roles_route_sql)
        local rbac_roles_api_delete_sql =
        fmt([[ DELETE FROM rbac_role_entities where role_id = %s and entity_id = %s; ]],
          escape(row.role_id),
          escape(api.id))
        insert(rbac_roles_sql, rbac_roles_api_delete_sql)
      end
    end

    --

    local sql = fmt([[
BEGIN;
  INSERT INTO services (id, created_at, updated_at, name, retries, protocol, host, port, path, connect_timeout, write_timeout, read_timeout)
       VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s);

  INSERT INTO routes (id, created_at, updated_at, service_id, protocols, methods, hosts, paths, regex_priority, strip_path, preserve_host)
       VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s);
%s
  DELETE FROM apis
        WHERE id = %s;
COMMIT;]],
      escape(service.id),
      escape(service.created_at, "timestamp"),
      escape(service.updated_at, "timestamp"),
      escape(service.name),
      escape(service.retries),
      escape(service.protocol),
      escape(service.host),
      escape(service.port),
      escape(service.path),
      escape(service.connect_timeout),
      escape(service.write_timeout),
      escape(service.read_timeout),
      escape(route.id),
      escape(route.created_at, "timestamp"),
      escape(route.updated_at, "timestamp"),
      escape(route.service_id),
      escape(route.protocols, "array"),
      escape(route.methods, "array"),
      escape(route.hosts, "array"),
      escape(route.paths, "array"),
      escape(route.regex_priority),
      escape(route.strip_path),
      escape(route.preserve_host),
      concat(plugins_sql) .. concat(workspace_sql) .. concat(rbac_roles_sql),
      escape(api.id)
    )

    migration_script[i] = sql

    logger("migrating api '%s' from workspace '%s' ...", api_name, workspace)
    logger.debug(sql)

    if not force and custom_plugins_count > 0 then
      logger("migrating api '%s' from workspace '%s' skipped (use -f to migrate apis with " ..
             "custom plugins", api_name, workspace)
      skipped = skipped + 1
      results.skipped[skipped] = {
        api = api,
        custom_plugins = custom_plugins,
      }

    else
      local res, err = self:query(sql)
      if not res then
        logger("migrating api '%s' from workspace '%s' failed (%s)", api_name, workspace, err)
        failed = failed + 1
        results.failed[failed] = {
          api = api,
          err = err,
        }

      else
        logger("migrating api '%s' from workspace '%s' done", api_name, workspace)
        migrated = migrated + 1
        results.migrated[migrated] = {
          api = api,
        }
      end
    end
  end

  if migrated > 0 then
    logger("%d/%d migrations succeeded", migrated, migrations.n)
  end

  if skipped > 0 then
    logger("%d/%d migrations skipped", skipped, migrations.n)
  end

  if failed > 0 then
    logger("%d/%d migrations failed", skipped, migrations.n)
  end

  migration_script = concat(migration_script, "\n\n")
  results.script = migration_script

  return results
end


function _mt:run_up_migration(name, up_sql)
  if type(name) ~= "string" then
    error("name must be a string", 2)
  end

  if type(up_sql) ~= "string" then
    error("up_sql must be a string", 2)
  end

  local conn = self:get_stored_connection()
  if not conn then
    error("no connection")
  end

  local sql = stringx.strip(up_sql)
  if sub(sql, -1) ~= ";" then
    sql = sql .. ";"
  end

  local sql = concat {
    "BEGIN;\n",
    sql, "\n",
    "COMMIT;\n",
  }

  local res, err = self:query(sql)
  if not res then
    self:query("ROLLBACK;")
    return nil, err
  end

  return true
end


function _mt:record_migration(subsystem, name, state)
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

  local key_escaped  = self:escape_literal("schema_meta")
  local subsystem_escaped = self:escape_literal(subsystem)
  local name_escaped = self:escape_literal(name)
  local name_array   = encode_array({ name })

  local sql
  if state == "executed" then
    sql = concat({
      "INSERT INTO schema_meta (key, subsystem, last_executed, executed)\n",
      "     VALUES (", key_escaped, ", ", subsystem_escaped, ", ", name_escaped, ", ", name_array, ")\n",
      "ON CONFLICT (key, subsystem) DO UPDATE\n",
      "        SET last_executed = EXCLUDED.last_executed,\n",
      "            executed = ARRAY_APPEND(COALESCE(schema_meta.executed, ARRAY[]::TEXT[]), ", name_escaped, ");",
    })

  elseif state == "pending" then
    sql = concat({
      "INSERT INTO schema_meta (key, subsystem, pending)\n",
      "     VALUES (", key_escaped, ", ", subsystem_escaped, ", ", name_array, ")\n",
      "ON CONFLICT (key, subsystem) DO UPDATE\n",
      "        SET pending = ARRAY_APPEND(schema_meta.pending, ", name_escaped, ");"
    })

  elseif state == "teardown" then
    sql = concat({
      "INSERT INTO schema_meta (key, subsystem, last_executed, executed)\n",
      "     VALUES (", key_escaped, ", ", subsystem_escaped, ", ", name_escaped, ", ", name_array, ")\n",
      "ON CONFLICT (key, subsystem) DO UPDATE\n",
      "        SET last_executed = EXCLUDED.last_executed,\n",
      "            executed = ARRAY_APPEND(COALESCE(schema_meta.executed, ARRAY[]::TEXT[]), ", name_escaped, "),\n",
      "            pending  = ARRAY_REMOVE(COALESCE(schema_meta.pending,  ARRAY[]::TEXT[]), ", name_escaped, ");",
    })

  else
    error("unknown 'state' argument: " .. tostring(state))
  end

  local res, err = self:query(sql)
  if not res then
    return nil, err
  end

  return true
end


function _mt:are_014_apis_present()
  local _, err = self:query([[
    DO $$
    BEGIN
      IF EXISTS(SELECT id FROM apis) THEN
        RAISE EXCEPTION 'there are apis in the db';
      END IF;
    EXCEPTION WHEN UNDEFINED_TABLE THEN
      -- Do nothing, table does not exist
    END;
    $$;
  ]])
  if err and err:match("there are apis in the db") then
    return true
  end
  if err then
    return nil, err
  end
  return false
end


function _mt:is_034()
  local res = {}

  local needed_migrations = {
    ["core"] = {
      "2015-01-12-175310_skeleton",
      "2015-01-12-175310_init_schema",
      "2015-11-23-817313_nodes",
      "2016-02-29-142793_ttls",
      "2016-09-05-212515_retries",
      "2016-09-16-141423_upstreams",
      "2016-12-14-172100_move_ssl_certs_to_core",
      "2016-11-11-151900_new_apis_router_1",
      "2016-11-11-151900_new_apis_router_2",
      "2016-11-11-151900_new_apis_router_3",
      "2016-01-25-103600_unique_custom_id",
      "2017-01-24-132600_upstream_timeouts",
      "2017-01-24-132600_upstream_timeouts_2",
      "2017-03-27-132300_anonymous",
      "2017-04-18-153000_unique_plugins_id",
      "2017-04-18-153000_unique_plugins_id_2",
      "2017-05-19-180200_cluster_events",
      "2017-05-19-173100_remove_nodes_table",
      "2017-06-16-283123_ttl_indexes",
      "2017-07-28-225000_balancer_orderlist_remove",
      "2017-10-02-173400_apis_created_at_ms_precision",
      "2017-11-07-192000_upstream_healthchecks",
      "2017-10-27-134100_consistent_hashing_1",
      "2017-11-07-192100_upstream_healthchecks_2",
      "2017-10-27-134100_consistent_hashing_2",
      "2017-09-14-121200_routes_and_services",
      "2017-10-25-180700_plugins_routes_and_services",
      "2017-06-20-100000_init_ratelimiting",
      "2017-07-31-993505_vitals_stats_seconds",
      "2017-08-30-892844_vitals_stats_minutes",
      "2017-08-30-892844_vitals_stats_hours",
      "2017-10-31-145721_vitals_stats_v0.30",
      "2017-10-31-145722_vitals_node_meta",
      "2017-11-13-145723_vitals_consumers",
      "2018-01-12-110000_workspaces",
      "2018-04-18-110000_old_rbac_cleanup",
      "2018-04-20-160000_rbac",
      "2018-08-15-100000_rbac_role_defaults",
      "2018-04-20-122000_rbac_defaults",
      "2018-04-20-122000_rbac_user_default_roles",
      "2018-02-01-000000_vitals_stats_v0.31",
      "2018-02-13-621974_portal_files_entity",
      "2018-03-12-000000_vitals_v0.32",
      "2018-04-25-000001_portal_initial_files",
      "2018-04-10-094800_dev_portal_consumer_types_statuses",
      "2018-04-10-094800_consumer_type_status_defaults",
      "2018-05-08-143700_consumer_dev_portal_columns",
      "2018-05-03-120000_credentials_master_table",
      "2017-05-15-110000_vitals_locks",
      "2018-03-12-000000_vitals_v0.33",
      "2018-06-12-105400_consumers_rbac_users_mapping",
      "2018-06-12-076222_consumer_type_status_admin",
      "2018-07-30-038822_remove_old_vitals_tables",
      "2018-08-07-114500_consumer_reset_secrets",
      "2018-08-14-000000_vitals_workspaces",
      "2018-09-05-144800_workspace_meta",
      "2018-10-03-120000_audit_requests_init",
      "2018-10-03-120000_audit_objects_init",
      "2018-10-05-144800_workspace_config",
      "2018-10-09-095247_create_entity_counters_table",
      "2018-10-17-160000_nested_workspaces_cleanup",
      "2018-10-17-170000_portal_files_to_files",
      "2018-10-24-000000_upgrade_admins",
      "2018-11-30-000000_case_insensitive_email"},
    ["response-transformer"] =
      {"2016-05-04-160000_resp_trans_schema_changes"},
    ["ip-restriction"] =
      {"2016-05-24-remove-cache"},
    ["statsd"] =
      {"2017-06-09-160000_statsd_schema_changes"},
    ["oauth2"] =
      {"2015-08-03-132400_init_oauth2",
       "2016-07-15-oauth2_code_credential_id",
       "2016-12-22-283949_serialize_redirect_uri",
       "2016-09-19-oauth2_api_id",
       "2016-12-15-set_global_credentials",
       "2017-04-24-oauth2_client_secret_not_unique",
       "2017-10-19-set_auth_header_name_default",
       "2017-10-11-oauth2_new_refresh_token_ttl_config_value",
       "2018-01-09-oauth2_pg_add_service_id"},
    ["jwt"] =
      {"2015-06-09-jwt-auth",
       "2016-03-07-jwt-alg",
       "2017-05-22-jwt_secret_not_unique",
       "2017-07-31-120200_jwt-auth_preflight_default",
       "2017-10-25-211200_jwt_cookie_names_default"},
    ["cors"] =
      {"2017-03-14_multiple_orgins"},
    ["basic-auth"] =
      {"2015-08-03-132400_init_basicauth",
       "2017-01-25-180400_unique_username"},
    ["key-auth"] =
      {"2015-07-31-172400_init_keyauth",
       "2017-07-31-120200_key-auth_preflight_default"},
    ["ldap-auth"] =
      {"2017-10-23-150900_header_type_default"},
    ["hmac-auth"] =
      {"2015-09-16-132400_init_hmacauth",
       "2017-06-21-132400_init_hmacauth"},
    ["datadog"] =
      {"2017-06-09-160000_datadog_schema_changes"},
    ["tcp-log"] =
      {"2017-12-13-120000_tcp-log_tls"},
    ["acl"] =
      {"2015-08-25-841841_init_acl"},
    ["admins"] =
      {"2018-06-30-000000_rbac_consumer_admins"},
    ["response-ratelimiting"] =
      {"2015-08-03-132400_init_response_ratelimiting",
       "2016-08-04-321512_response-rate-limiting_policies",
       "2017-12-19-120000_add_route_and_service_id_to_response_ratelimiting"},
    ["request-transformer"] =
      {"2016-05-04-160000_req_trans_schema_changes"},
    ["default_workspace"] =
      {"2018-02-16-110000_default_workspace_entities"},
    ["rate-limiting"] =
      {"2015-08-03-132400_init_ratelimiting_plugin_reimport_ee",
       "2016-07-25-471385_ratelimiting_policies",
       "2017-11-30-120000_add_route_and_service_id"},
    ["kong_admin_basic_auth"] =
      {"2018-11-08-000000_kong_admin_basic_auth"},
    ["workspace_counters"] =
      {"2018-10-11-164515_fill_counters"}
  }

  local rows, err = self:query([[
    SELECT to_regclass('schema_migrations') AS "name";
  ]])
  if err then
    return nil, err
  end

  if not rows or not rows[1] or rows[1].name ~= "schema_migrations" then
    -- no trace of legacy migrations: above 0.14
    return res
  end

  local schema_migrations_rows, err = self:query([[
    SELECT "id", "migrations" FROM "schema_migrations";
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
      -- missing all migrations for a component: below 0.34
      res.invalid_state = true
      res.missing_component = name
      return res
    end

    for _, needed_migration in ipairs(migrations) do
      local found

      for _, current_migration in ipairs(current_migrations) do
        if current_migration == needed_migration then
          found = true
          break
        end
      end

      if not found then
        -- missing at least one migration for a component: below 0.34
        res.invalid_state = true
        res.missing_component = name
        res.missing_migration = needed_migration
        return res
      end
    end
  end

  -- all migrations match: 0.34 install
  res.is_034 = true

  return res
end


function _mt:migrate_core_entities(opts)
  local migrate_core_entities = require "kong.enterprise_edition.db.migrations.migrate_core_entities"
  return migrate_core_entities(self, "postgres", opts)
end


local _M = {}


function _M.new(kong_config)
  local config = {
    host       = kong_config.pg_host,
    port       = kong_config.pg_port,
    timeout    = kong_config.pg_timeout,
    user       = kong_config.pg_user,
    password   = kong_config.pg_password,
    database   = kong_config.pg_database,
    schema     = "",
    ssl        = kong_config.pg_ssl,
    ssl_verify = kong_config.pg_ssl_verify,
    cafile     = kong_config.lua_ssl_trusted_certificate,
  }

  local db = pgmoon.new(config)

  return setmetatable({
    config            = config,
    escape_identifier = db.escape_identifier,
    escape_literal    = db.escape_literal,
  }, _mt)
end


return _M
