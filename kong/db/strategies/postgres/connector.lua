local logger       = require "kong.cmd.utils.log"
local pgmoon       = require "pgmoon"
local arrays       = require "pgmoon.arrays"
local stringx      = require "pl.stringx"
local semaphore    = require "ngx.semaphore"


local setmetatable = setmetatable
local encode_array = arrays.encode_array
local tonumber     = tonumber
local tostring     = tostring
local concat       = table.concat
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
local ERR                           = ngx.ERR
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


local function get_table_names(self, excluded)
  local i = 0
  local table_names = {}
  for row, err in self:iterate(SQL_INFORMATION_SCHEMA_TABLES) do
    if err then
      return nil, err
    end

    if not excluded or not excluded[row.table_name] then
      i = i + 1
      table_names[i] = self:escape_identifier(row.table_name)
    end
  end

  return table_names
end


local function reset_schema(self)
  local table_names, err = get_table_names(self)
  if not table_names then
    return nil, err
  end

  local drop_tables
  if #table_names == 0 then
    drop_tables = ""
  else
    drop_tables = concat {
      "    DROP TABLE IF EXISTS ", concat(table_names, ", "), " CASCADE;\n"
    }
  end

  local schema = self:escape_identifier(self.config.schema)
  local ok, err = self:query(concat {
    "BEGIN;\n",
    "  DO $$\n",
    "  BEGIN\n",
    "    DROP SCHEMA IF EXISTS ", schema, " CASCADE;\n",
    "    CREATE SCHEMA IF NOT EXISTS ", schema, " AUTHORIZATION CURRENT_USER;\n",
    "    GRANT ALL ON SCHEMA ", schema ," TO CURRENT_USER;\n",
    "  EXCEPTION WHEN insufficient_privilege THEN\n", drop_tables,
    "  END;\n",
    "  $$;\n",
    "    SET SCHEMA ",  self:escape_literal(self.config.schema), ";\n",
    "COMMIT;",  })

  if not ok then
    return nil, err
  end

  return true
end


local setkeepalive


local function connect(config)
  local phase  = get_phase()
  if phase == "init" or phase == "init_worker" or ngx.IS_CLI then
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


local _mt = {
  reset = reset_schema
}


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
    return nil, "failed to retrieve PostgreSQL server_version_num: " .. err
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
    local graph = tsort.new()

    graph:add("cluster_events")

    for _, strategy in pairs(strategies) do
      local schema = strategy.schema
      if schema.ttl then
        local name = schema.name
        graph:add(name)
        for _, field in schema:each_field() do
          if field.type == "foreign" and field.schema.ttl then
            graph:add(name, field.schema.name)
          end
        end
      end
    end

    local sorted_strategies = graph:sort()
    local ttl_escaped = self:escape_identifier("ttl")
    local expire_at_escaped = self:escape_identifier("expire_at")
    local cleanup_statements = {}
    local cleanup_statements_count = #sorted_strategies
    for i = 1, cleanup_statements_count do
      local table_name = sorted_strategies[i]
      local column_name = table_name == "cluster_events" and expire_at_escaped
                                                          or ttl_escaped
      cleanup_statements[i] = concat {
        "  DELETE FROM ",
        self:escape_identifier(table_name),
        " WHERE ",
        column_name,
        " < CURRENT_TIMESTAMP AT TIME ZONE 'UTC';"
      }
    end

    local cleanup_statement = concat(cleanup_statements, "\n")

    return timer_every(60, function(premature)
      if premature then
        return
      end

      local ok, err, _, num_queries = self:query(cleanup_statement)
      if not ok then
        if num_queries then
          for i = num_queries + 1, cleanup_statements_count do
            local statement = cleanup_statements[i]
            local ok, err = self:query(statement)
            if not ok then
              if err then
                log(WARN, "unable to clean expired rows from table '",
                          sorted_strategies[i], "' on PostgreSQL database (",
                          err, ")")
              else
                log(WARN, "unable to clean expired rows from table '",
                          sorted_strategies[i], "' on PostgreSQL database")
              end
            end
          end

        else
          log(ERR, "unable to clean expired rows from PostgreSQL database (", err, ")")
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
    strategy  = "PostgreSQL",
    db_name   = self.config.database,
    db_schema = self.config.schema,
    db_desc   = "database",
    db_ver    = db_ver or "unknown",
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


function _mt:acquire_query_semaphore_resource()
  if not self.sem then
    return true
  end

  do
    local phase = get_phase()
    if phase == "init" or phase == "init_worker" then
      return true
    end
  end

  local ok, err = self.sem:wait(self.config.sem_timeout)
  if not ok then
    return nil, err
  end

  return true
end


function _mt:release_query_semaphore_resource()
  if not self.sem then
    return true
  end

  do
    local phase = get_phase()
    if phase == "init" or phase == "init_worker" then
      return true
    end
  end

  self.sem:post()
end


function _mt:query(sql)
  local res, err, partial, num_queries

  local ok
  ok, err = self:acquire_query_semaphore_resource()
  if not ok then
    return nil, "error acquiring query semaphore: " .. err
  end

  local conn = self:get_stored_connection()
  if conn then
    res, err, partial, num_queries = conn:query(sql)

  else
    local connection
    connection, err = connect(self.config)
    if not connection then
      self:release_query_semaphore_resource()
      return nil, err
    end

    res, err, partial, num_queries = connection:query(sql)

    setkeepalive(connection)
  end

  self:release_query_semaphore_resource()

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


function _mt:truncate()
  local table_names, err = get_table_names(self, PROTECTED_TABLES)
  if not table_names then
    return nil, err
  end

  if #table_names == 0 then
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
  logger.debug("creating 'locks' table if not existing...")

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

  logger.debug("successfully created 'locks' table")

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
    "DELETE\n",
    "  FROM ", self:escape_identifier("locks"), "\n",
    " WHERE ", self:escape_identifier("key"), "   = ", self:escape_literal(key), "\n",
    "   AND ", self:escape_identifier("owner"), " = ", self:escape_literal(owner), ";"
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

  local table_names, err = get_table_names(self)
  if not table_names then
    return nil, err
  end

  local schema_meta_table_name = self:escape_identifier("schema_meta")
  local schema_meta_table_exists
  for _, table_name in ipairs(table_names) do
    if table_name == schema_meta_table_name then
      schema_meta_table_exists = true
      break
    end
  end

  if not schema_meta_table_exists then
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

  -- create schema if not exists

  logger.debug("creating '%s' schema if not existing...", self.config.schema)

  local schema = self:escape_identifier(self.config.schema)
  local ok, err = self:query(concat {
    "BEGIN;\n",
    "  DO $$\n",
    "  BEGIN\n",
    "    CREATE SCHEMA IF NOT EXISTS ", schema, " AUTHORIZATION CURRENT_USER;\n",
    "    GRANT ALL ON SCHEMA ", schema ," TO CURRENT_USER;\n",
    "  EXCEPTION WHEN insufficient_privilege THEN\n",
    "    -- Do nothing, perhaps the schema has been created already\n",
    "  END;\n",
    "  $$;\n",
    "  SET SCHEMA ",  self:escape_literal(self.config.schema), ";\n",
    "COMMIT;",
  })

  if not ok then
    return nil, err
  end

  logger.debug("successfully created '%s' schema", self.config.schema)

  -- create schema meta table if not exists

  logger.debug("creating 'schema_meta' table if not existing...")

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

  logger.debug("successfully created 'schema_meta' table")

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

  return reset_schema(self)
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


local _M = {}


function _M.new(kong_config)
  local config = {
    host        = kong_config.pg_host,
    port        = kong_config.pg_port,
    timeout     = kong_config.pg_timeout,
    user        = kong_config.pg_user,
    password    = kong_config.pg_password,
    database    = kong_config.pg_database,
    schema      = kong_config.pg_schema or "",
    ssl         = kong_config.pg_ssl,
    ssl_verify  = kong_config.pg_ssl_verify,
    cafile      = kong_config.lua_ssl_trusted_certificate,
    sem_max     = kong_config.pg_max_concurrent_queries or 0,
    sem_timeout = (kong_config.pg_semaphore_timeout or 60000) / 1000,
  }

  local db = pgmoon.new(config)

  local sem
  if config.sem_max > 0 then
    local err
    sem, err = semaphore.new(config.sem_max)
    if not sem then
      ngx.log(ngx.CRIT, "failed creating the PostgreSQL connector semaphore: ",
                        err)
    end
  end

  return setmetatable({
    config            = config,
    escape_identifier = db.escape_identifier,
    escape_literal    = db.escape_literal,
    sem               = sem,
  }, _mt)
end


return _M
