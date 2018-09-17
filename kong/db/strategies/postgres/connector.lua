local pgmoon       = require "pgmoon"


local setmetatable = setmetatable
local concat       = table.concat
local ipairs       = ipairs
local pairs        = pairs
local type         = type
local ngx          = ngx
local timer_every  = ngx.timer.every
local update_time  = ngx.update_time
local get_phase    = ngx.get_phase
local null         = ngx.null
local now          = ngx.now
local log          = ngx.log


local WARN                          = ngx.WARN
local SQL_INFORMATION_SCHEMA_TABLES = [[
SELECT table_name
  FROM information_schema.tables
 WHERE table_schema = 'public';
]]


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

  local ok, err = connection:connect()
  if not ok then
    return nil, err
  end

  if connection.sock:getreusedtimes() == 0 then
    ok, err = connection:query("SET TIME ZONE 'UTC';");
    if not ok then
      setkeepalive(connection)
      return nil, err
    end
  end

  return connection
end


setkeepalive = function(connection)
  if not connection or not connection.sock then
    return nil, "no active connection"
  end

  local ok, err
  if connection.sock_type == "luasocket" then
    ok, err = connection:disconnect()
    if not ok then
      if err then
        log(WARN, "unable to close postgres connection (", err, ")")

      else
        log(WARN, "unable to close postgres connection")
      end

      return nil, err
    end

  else
    ok, err = connection:keepalive()
    if not ok then
      if err then
        log(WARN, "unable to set keepalive for postgres connection (", err, ")")

      else
        log(WARN, "unable to set keepalive for postgres connection")
      end

      return nil, err
    end
  end

  return true
end


local _mt = {}


_mt.__index = _mt


local function extract_major_minor(release_version)
  return string.match(release_version, "^(%d+%.%d+)")
end


function _mt:init()
  local res, err = self:query("SHOW server_version;")
  if not res then
    return nil, "failed to retrieve server_version: " .. err
  end

  if #res < 1 or not res[1].server_version then
    return nil, "failed to retrieve server_version"
  end

  self.major_minor_version = extract_major_minor(res[1].server_version)
  if not self.major_minor_version then
    return nil, "failed to extract major.minor version from '" ..
                res[1].server_version .. "'"
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
        " < CURRENT_TIMESTAMP;"
      }
    end

    cleanup_statement = concat({
      "BEGIN;",
      concat(cleanup_statement, "\n"),
      "COMMIT;"
    }, "\n")

    return timer_every(60, function()
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
  return {
    strategy = "PostgreSQL",
    db_name = self.config.database,
    db_desc = "database",
    db_ver = self.major_minor_version or "unknown",
  }
end


function _mt:connect()
  if self.connection and self.connection.sock then
    return true
  end

  local connection, err = connect(self.config)
  if not connection then
    return nil, err
  end

  self.connection = connection

  return true
end


function _mt:setkeepalive()
  local ok, err = setkeepalive(self.connection)

  self.connection = nil

  if not ok then
    return nil, err
  end

  return true
end


function _mt:query(sql)
  if self.connection and self.connection.sock then
    return self.connection:query(sql)
  end

  local connection, err = connect(self.config)
  if not connection then
    return nil, err
  end

  local res, exc, partial, num_queries = connection:query(sql)

  setkeepalive(connection)

  return res, exc, partial, num_queries
end


function _mt:iterate(sql)
  local res, err, partial, num_queries = self:query(sql)
  if not res then
    return nil, err, partial, num_queries
  end

  if res == true then
    return iterator { true }
  end

  return iterator(res)
end


function _mt:reset()
  local user = self:escape_identifier(self.config.user)
  local ok, err = self:query(concat {
    "BEGIN;\n",
    "  DROP SCHEMA IF EXISTS public CASCADE;\n",
    "  CREATE SCHEMA IF NOT EXISTS public AUTHORIZATION ", user, ";\n",
    "  GRANT ALL ON SCHEMA public TO ", user, ";\n",
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
    if table_name ~= "schema_migrations" then
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


function _mt:setup_locks(_)
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

  return true
end


function _mt:insert_lock(key, ttl, owner)
  local ttl_escaped = concat {
                        "TO_TIMESTAMP(",
                        self:escape_literal(now_updated() + ttl),
                        ") AT TIME ZONE 'UTC'"
                      }

  local sql = concat { "BEGIN;\n",
                       "  DELETE FROM locks\n",
                       "        WHERE ttl < CURRENT_TIMESTAMP;\n",
                       "  INSERT INTO locks (key, owner, ttl)\n",
                       "       VALUES (", self:escape_literal(key),   ", ",
                                          self:escape_literal(owner), ", ",
                                          ttl_escaped, ")\n",
                       "  ON CONFLICT DO NOTHING;\n",
                       "COMMIT;"
  }

  local res, err_or_num_queries = self:query(sql)
  if not res then
    return nil, err_or_num_queries
  end

  if err_or_num_queries ~= 4 then
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
    " WHERE key   = ", self:escape_literal(key), "\n",
    "   AND owner = ", self:escape_literal(owner), ";"
  }

  local res, err = self:query(sql)
  if not res then
    return nil, err
  end

  return true
end


local _M = {}


function _M.new(kong_config)
  local config = {
    host       = kong_config.pg_host,
    port       = kong_config.pg_port,
    user       = kong_config.pg_user,
    password   = kong_config.pg_password,
    database   = kong_config.pg_database,
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
