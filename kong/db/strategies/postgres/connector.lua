local pgmoon       = require "pgmoon"


local setmetatable = setmetatable
local tonumber     = tonumber
local tostring     = tostring
local concat       = table.concat
local floor        = math.floor
local fmt          = string.format
--local pairs        = pairs
--local type         = type
local ngx          = ngx
local get_phase    = ngx.get_phase
local null         = ngx.null
local log          = ngx.log


local WARN                          = ngx.WARN
local SQL_INFORMATION_SCHEMA_TABLES = [[
SELECT table_name
  FROM information_schema.tables
 WHERE table_schema = 'public';
]]


--local function visit(k, n, m, s)
--  if m[k] == 0 then return 1 end
--  if m[k] == 1 then return end
--  m[k] = 0
--  local f = n[k]
--  for i=1, #f do
--    if visit(f[i], n, m, s) then return 1 end
--  end
--  m[k] = 1
--  s[#s+1] = k
--end
--
--
--local tsort = {}
--tsort.__index = tsort
--
--
--function tsort.new()
--  return setmetatable({ n = {} }, tsort)
--end
--
--
--function tsort:add(...)
--  local p = { ... }
--  local c = #p
--  if c == 0 then return self end
--  if c == 1 then
--    p = p[1]
--    if type(p) == "table" then
--      c = #p
--    else
--      p = { p }
--    end
--  end
--  local n = self.n
--  for i=1, c do
--    local f = p[i]
--    if n[f] == nil then n[f] = {} end
--  end
--  for i=2, c, 1 do
--    local f = p[i]
--    local t = p[i-1]
--    local o = n[f]
--    o[#o+1] = t
--  end
--  return self
--end
--
--
--function tsort:sort()
--  local n  = self.n
--  local s = {}
--  local m  = {}
--  for k in pairs(n) do
--    if m[k] == nil then
--      if visit(k, n, m, s) then
--        return nil, "There is a circular dependency in the graph. It is not possible to derive a topological sort."
--      end
--    end
--  end
--  return s
--end


local function iterator(rows)
  local i = 0
  return function()
    i = i + 1
    return rows[i]
  end
end


local _mt = {}


_mt.__index = _mt


function _mt:init()
  local res, err = self:query("SHOW server_version_num;")
  local ver = tonumber(res and res[1] and res[1].server_version_num)
  if not ver then
    return nil, err or "postgres version not detected"
  end

  self.version_num = ver


  local major = floor(ver / 10000)
  if major < 10 then
    self.major_version = fmt("%u.%u", major, floor(ver / 100 % 100))
    self.minor_version = tostring(ver % 100)

  else
    self.major_version = tostring(major)
    self.minor_version = tostring(ver % 100)
  end

  self.version = fmt("%s.%s", self.major_version, self.minor_version)

  return true
end


function _mt:connect()
  local connection = self.connection

  if connection then
    return true
  end

  local config = self.config
  local phase  = get_phase()

  if phase == "init" or phase == "init_worker" or ngx.IS_CLI then
    config.socket_type = "luasocket"

  else
    config.socket_type = "nginx"
  end

  local db = pgmoon.new(config)

  db.convert_null = true
  db.NULL         = null

  local ok, err = db:connect()
  if not ok then
    return nil, err
  end

  self.connection = db

  if db.sock:getreusedtimes() == 0 then
    ok, err = self:query("SET TIME ZONE 'UTC';");
    if not ok then
      return nil, err
    end
  end

  return true
end


function _mt:setkeepalive()
  local connection = self.connection

  self.connection  = nil

  if not connection then
    return nil, "no active connection"
  end

  local ok, err

  if connection.sock_type == "luasocket" then
    ok, err = connection:disconnect()

  else
    ok, err = connection:keepalive()
  end

  if not ok then
    return nil, err
  end

  return true
end


function _mt:query(sql)
  local connection = self.connection

  if connection then
    return connection:query(sql)
  end

  local ok, err = self:connect()
  if not ok then
    return nil, err
  end

  local res, exc, partial, num_queries = self.connection:query(sql)
  ok, err = self:setkeepalive()

  if not ok then
    log(WARN, err)
  end

  if not res then
    return nil, exc, partial, num_queries
  end

  return res, exc
end


function _mt:iterate(sql)
  local connection = self.connection

  if connection then
    local res, err, partial, num_queries = connection:query(sql)
    if not res then
      return nil, err, partial, num_queries
    end

    if res == true then
      return iterator { true }
    end

    return iterator(res)
  end

  local ok, err = self:connect()
  if not ok then
    return nil, err
  end

  local res, exc, partial, num_queries = self.connection:query(sql)

  ok, err = self:setkeepalive()

  if not ok then
    log(WARN, err)
  end

  if not res then
    return nil, exc, partial, num_queries
  end

  if res == true then
    return iterator { true }
  end

  return iterator(res)
end


function _mt:reset()
  local user = self:escape_identifier(self.config.user)

  local ok, err = self:connect()
  if not ok then
    return nil, err
  end

  ok, err = self:query(concat {
    "BEGIN;\n",
    "DROP SCHEMA IF EXISTS public CASCADE;\n",
    "CREATE SCHEMA IF NOT EXISTS public AUTHORIZATION " .. user .. ";\n",
    "GRANT ALL ON SCHEMA public TO " .. user .. ";\n",
    "COMMIT;\n",
  })

  local success, exc = self:setkeepalive()
  if not success then
    log(WARN, exc)
  end

  if not ok then

    return nil, err
  end

  --[[
  -- Disabled for now because migrations will run from the old DAO.
  -- Additionally, the purpose of `reset()` is to clean the database,
  -- and leave it blank. Migrations will use it to reset the database,
  -- and migrations will also be responsible for creating the necessary
  -- tables.
  local graph = tsort.new()
  local hash  = {}

  for _, strategy in pairs(strategies) do
    local schema = strategy.schema
    local name   = schema.name
    local fields = schema.fields

    hash[name]   = strategy
    graph:add(name)

    for _, field in ipairs(fields) do
      if field.type == "foreign" then
        graph:add(field.schema.name, name)
      end
    end
  end

  local sorted_strategies = graph:sort()

  for _, name in ipairs(sorted_strategies) do
    ok, err = hash[name]:create()
    if not ok then
      return nil, err
    end
  end
  --]]

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

  local truncate_statement  = {
    "TRUNCATE TABLE ", concat(table_names, ", "), " RESTART IDENTITY CASCADE;"
  }

  local ok, err = self:query(truncate_statement)
  if not ok then

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
