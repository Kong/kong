local pgmoon = require "pgmoon"
local Errors = require "kong.dao.errors"
local utils = require "kong.tools.utils"
local cjson = require "cjson"

local get_phase = ngx.get_phase
local timer_at = ngx.timer.at
local tostring = tostring
local ngx_log = ngx.log
local concat = table.concat
local ipairs = ipairs
local pairs = pairs
local match = string.match
local type = type
local find = string.find
local uuid = utils.uuid
local ceil = math.ceil
local fmt = string.format
local ERR = ngx.ERR

local TTL_CLEANUP_INTERVAL = 60 -- 1 minute

local function log(lvl, ...)
  return ngx_log(lvl, "[postgres] ", ...)
end

local _M = require("kong.dao.db").new_db("postgres")

-- force the use of luasocket for pgmoon connections where
-- lua-nginx-module's socket interface is unavailable. pgmoon handles the
-- master init phase on its own, but we need some extra logic wrapping
-- keepalive et al, so we explicitly declare socket_type for init as well
local forced_luasocket_phases = {
  init        = true,
  init_worker = true,
}

_M.dao_insert_values = {
  id = function()
    return uuid()
  end
}

_M.additional_tables = {
  "ttls",
  "cluster_events",
  "routes",
  "services",
  "consumers",
  "plugins",
  "certificates",
  "snis",
}

function _M.new(kong_config)
  local self = _M.super.new()

  self.query_options = {
    host = kong_config.pg_host,
    port = kong_config.pg_port,
    timeout = kong_config.pg_timeout,
    user = kong_config.pg_user,
    password = kong_config.pg_password,
    database = kong_config.pg_database,
    ssl = kong_config.pg_ssl,
    ssl_verify = kong_config.pg_ssl_verify,
    cafile = kong_config.lua_ssl_trusted_certificate
  }

  return self
end

local function query_opts(self)
  local opts = self:clone_query_options()

  if ngx.IS_CLI or forced_luasocket_phases[get_phase()] then
    -- Force LuaSocket usage in order to allow for self-signed certificates
    -- to be trusted (via opts.cafile) in the resty-cli interpreter.
    -- As usual, LuaSocket is also forced in non-supported cosocket contexts.
    opts.socket_type = "luasocket"

  else
    opts.socket_type = "nginx"
  end

  return opts
end

function _M:infos()
  return {
    db_name = "PostgreSQL",
    desc = "database",
    name = self:clone_query_options().database,
    version = self.major_minor_version or "unknown",
  }
end

local do_clean_ttl

function _M.extract_major_minor(release_version)
  return match(release_version, "^(%d+%.%d+)")
end

function _M:init()
  local res, err = self:query("SHOW server_version;")
  if not res then
    return nil, Errors.db("could not retrieve server_version: " .. err)
  end

  if #res < 1 or not res[1].server_version then
    return nil, Errors.db("could not retrieve server_version")
  end

  self.major_minor_version = _M.extract_major_minor(res[1].server_version)
  if not self.major_minor_version then
    return nil, Errors.db("could not extract major.minor version")
  end

  return true
end

function _M:init_worker()
  local ok, err = timer_at(TTL_CLEANUP_INTERVAL, do_clean_ttl, self)
  if not ok then
    log(ERR, "could not create TTL timer: ", err)
  end
  return true
end

--- TTL utils
-- @section ttl_utils

local cached_columns_types = {}

local function retrieve_primary_key_type(self, schema, table_name)
  local col_type = cached_columns_types[table_name]

  if not col_type then
    local query = fmt([[
      SELECT data_type
      FROM information_schema.columns
      WHERE table_name = '%s'
        and column_name = '%s'
      LIMIT 1]], table_name, schema.primary_key[1])

    local res, err = self:query(query)
    if not res then return nil, err
    elseif #res > 0 then
      col_type = res[1].data_type
      cached_columns_types[table_name] = col_type
    end
  end

  return col_type
end

local function ttl(self, tbl, table_name, schema, ttl)
  if not schema.primary_key or #schema.primary_key ~= 1 then
    return nil, "cannot set a TTL if the entity has no primary key, or has more than one primary key"
  end

  local primary_key_type, err = retrieve_primary_key_type(self, schema, table_name)
  if not primary_key_type then
    return nil, err
  end

  -- get current server time, in milliseconds, but with SECOND precision
  local query = [[
    SELECT extract(epoch from now() at time zone 'utc')::bigint*1000 as timestamp;
  ]]
  local res, err = self:query(query)
  if not res then
    return nil, err
  end

  -- the expiration is always based on the current time
  local expire_at = res[1].timestamp + (ttl * 1000)

  local query = fmt([[
    SELECT upsert_ttl('%s', %s, '%s', '%s', to_timestamp(%d/1000) at time zone 'UTC')
  ]], tbl[schema.primary_key[1]],
      primary_key_type == "uuid" and "'" .. tbl[schema.primary_key[1]] .. "'" or "NULL",
      schema.primary_key[1], table_name, expire_at)
  local res, err = self:query(query)
  if not res then
    return nil, err
  end
  return true
end

local function clear_expired_ttl(self)
  local query = [[
    SELECT * FROM ttls WHERE expire_at < CURRENT_TIMESTAMP(0) at time zone 'utc'
  ]]
  local res, err = self:query(query)
  if not res then
    return nil, err
  end

  for _, v in ipairs(res) do
    local delete_entity_query = fmt("DELETE FROM %s WHERE %s='%s'", v.table_name,
                                    v.primary_key_name, v.primary_key_value)
    local res, err = self:query(delete_entity_query)
    if not res then
      return nil, err
    end

    local delete_ttl_query = fmt([[
      DELETE FROM ttls
      WHERE primary_key_value='%s'
        AND table_name='%s']], v.primary_key_value, v.table_name)
    res, err = self:query(delete_ttl_query)
    if not res then
      return nil, err
    end
  end

  return true
end

-- for tests
_M.clear_expired_ttl = clear_expired_ttl

do_clean_ttl = function(premature, self)
  if premature then
    return
  end

  local ok, err = clear_expired_ttl(self)
  if not ok then
    log(ERR, "could not cleanup TTLs: ", err)
  end

  ok, err = timer_at(TTL_CLEANUP_INTERVAL, do_clean_ttl, self)
  if not ok then
    log(ERR, "could not create TTL timer: ", err)
  end
end

--- Query building
-- @section query_building

-- @see pgmoon
local function escape_identifier(ident)
  return '"' .. (tostring(ident):gsub('"', '""')) .. '"'
end

-- @see pgmoon
local function escape_literal(val, field)
  if val == ngx.null then
    return "NULL"
  end

  local t_val = type(val)
  if t_val == "number" then
    return tostring(val)
  elseif t_val == "string" then
    return "'" .. tostring((val:gsub("'", "''"))) .. "'"
  elseif t_val == "boolean" then
    return val and "TRUE" or "FALSE"
  elseif t_val == "table" and field and (field.type == "table" or field.type == "array") then
    return escape_literal(cjson.encode(val))
  end
  error("don't know how to escape value: " .. tostring(val))
end

local function get_where(tbl)
  local where = {}

  for col, value in pairs(tbl) do
    where[#where+1] = fmt("%s = %s",
                          escape_identifier(col),
                          escape_literal(value))
  end

  return concat(where, " AND ")
end

local function get_select_fields(schema)
  local fields = {}
  for k, v in pairs(schema.fields) do
    if v.type == "timestamp" then
      fields[#fields+1] = fmt("(extract(epoch from %s)*1000)::bigint as %s", k, k)
    else
      fields[#fields+1] = '"' .. k .. '"'
    end
  end
  return concat(fields, ", ")
end

local function select_query(self, select_clause, schema, table, where, offset, limit)
  local query

  local join_ttl = schema.primary_key and #schema.primary_key == 1
  if join_ttl then
    local primary_key_type, err = retrieve_primary_key_type(self, schema, table)
    if not primary_key_type then
      return nil, err
    end

    query = fmt([[
      SELECT %s FROM %s
      LEFT OUTER JOIN ttls ON (%s.%s = ttls.primary_%s_value)
      WHERE (ttls.primary_key_value IS NULL
       OR (ttls.table_name = '%s' AND expire_at > CURRENT_TIMESTAMP(0) at time zone 'utc'))
    ]], select_clause, table, table, schema.primary_key[1],
        primary_key_type == "uuid" and "uuid" or "key", table)
  else
    query = fmt("SELECT %s FROM %s", select_clause, table)
  end

  if where then
    query = query .. (join_ttl and " AND " or " WHERE ") .. where
  end
  if limit then
    query = query .. " LIMIT " .. limit
  end
  if offset and offset > 0 then
    query = query .. " OFFSET " .. offset
  end
  return query
end

--- Querying
-- @section querying

local function parse_error(err_str)
  local err
  if find(err_str, "Key .* already exists") then
    local col, value = match(err_str, "%((.+)%)=%((.+)%)")
    if col then
      err = Errors.unique {[col] = value}
    end
  elseif find(err_str, "violates foreign key constraint") then
    local col, value = match(err_str, "%((.+)%)=%((.+)%)")
    if col then
      err = Errors.foreign {[col] = value}
    end
  end

  return err or Errors.db(err_str)
end

local function deserialize_rows(rows, schema)
  for i, row in ipairs(rows) do
    for col, value in pairs(row) do
      if type(value) == "string" and schema.fields[col] and
        (schema.fields[col].type == "table" or schema.fields[col].type == "array") then
        rows[i][col] = cjson.decode(value)
      end
    end
  end
end

function _M:query(query, schema)
  local conn_opts = query_opts(self)
  local pg = pgmoon.new(conn_opts)

  if conn_opts.timeout then
    pg:settimeout(conn_opts.timeout)
  end

  local ok, err = pg:connect()
  if not ok then
    return nil, Errors.db(err)
  end

  local res, err = pg:query(query)
  if conn_opts.socket_type == "nginx" then
    pg:keepalive()
  else
    pg:disconnect()
  end

  if not res then return nil, parse_error(err)
  elseif schema then
    deserialize_rows(res, schema)
  end

  return res
end

local function deserialize_timestamps(self, row, schema)
  local result = row
  for k, v in pairs(schema.fields) do
    if v.type == "timestamp" and result[k] then
      local query = fmt([[
        SELECT (extract(epoch from timestamp '%s') * 1000) as %s;
      ]], result[k], k)
      local res, err = self:query(query)
      if not res then return nil, err
      elseif #res > 0 then
        result[k] = res[1][k]
      end
    end
  end
  return result
end

local function serialize_timestamps(self, tbl, schema)
  local result = tbl
  for k, v in pairs(schema.fields) do
    if v.type == "timestamp" and result[k] then
      local query = fmt([[
        SELECT to_timestamp(%f) at time zone 'UTC' as %s;
      ]], result[k] / 1000, k)
      local res, err = self:query(query)
      if not res then return nil, err
      elseif #res <= 1 then
        result[k] = res[1][k]
      end
    end
  end
  return result
end

function _M:insert(table_name, schema, model, _, options)
  options = options or {}

  local values, err = serialize_timestamps(self, model, schema)
  if err then
    return nil, err
  end

  local cols, args = {}, {}
  for col, value in pairs(values) do
    cols[#cols+1] = escape_identifier(col)
    args[#args+1] = escape_literal(value, schema.fields[col])
  end

  local query = fmt("INSERT INTO %s(%s) VALUES(%s) RETURNING *",
                    table_name,
                    concat(cols, ", "),
                    concat(args, ", "))
  local res, err = self:query(query, schema)
  if not res then return nil, err
  elseif #res > 0 then
    res, err = deserialize_timestamps(self, res[1], schema)
    if err then return nil, err
    else
      -- Handle options
      if options.ttl then
        local ok, err = ttl(self, res, table_name, schema, options.ttl)
        if not ok then
          return nil, err
        end
      end
      return res
    end
  end
end

function _M:find(table_name, schema, primary_keys)
  local where = get_where(primary_keys)
  local query = select_query(self, get_select_fields(schema), schema, table_name, where)
  local rows, err = self:query(query, schema)
  if not rows then       return nil, err
  elseif #rows <= 1 then return rows[1]
  else                   return nil, "bad rows result" end
end

function _M:find_all(table_name, tbl, schema)
  local where
  if tbl then
    where = get_where(tbl)
  end

  local query = select_query(self, get_select_fields(schema), schema, table_name, where)
  return self:query(query, schema)
end

function _M:find_page(table_name, tbl, page, page_size, schema)
  page = page or 1

  local total_count, err = self:count(table_name, tbl, schema)
  if not total_count then
    return nil, err
  end

  local total_pages = ceil(total_count/page_size)
  local offset = page_size * (page - 1)

  local where
  if tbl then
    where = get_where(tbl)
  end

  local query = select_query(self, get_select_fields(schema), schema, table_name, where, offset, page_size)
  local rows, err = self:query(query, schema)
  if not rows then
    return nil, err
  end

  local next_page = page + 1
  return rows, nil, (next_page <= total_pages and next_page or nil)
end

function _M:count(table_name, tbl, schema)
  local where
  if tbl then
    where = get_where(tbl)
  end

  local query = select_query(self, "COUNT(*)", schema, table_name, where)
  local res, err = self:query(query)
  if not res then       return nil, err
  elseif #res <= 1 then return res[1].count
  else                  return nil, "bad rows result" end
end

function _M:update(table_name, schema, _, filter_keys, values, nils, full, _, options)
  options = options or {}

  local args = {}
  local values, err = serialize_timestamps(self, values, schema)
  if not values then
    return nil, err
  end

  for col, value in pairs(values) do
    args[#args+1] = fmt("%s = %s",
                        escape_identifier(col),
                        escape_literal(value, schema.fields[col]))
  end

  if full then
    for col in pairs(nils) do
      args[#args+1] = escape_identifier(col) .. " = NULL"
    end
  end

  local where = get_where(filter_keys)
  local query = fmt("UPDATE %s SET %s WHERE %s RETURNING *",
                    table_name,
                    concat(args, ", "),
                    where)

  local res, err = self:query(query, schema)
  if not res then return nil, err
  elseif res.affected_rows == 1 then
    res, err = deserialize_timestamps(self, res[1], schema)
    if not res then return nil, err
    elseif options.ttl then
      local ok, err = ttl(self, res, table_name, schema, options.ttl)
      if not ok then
        return nil, err
      end
    end
    return res
  end
end

function _M:delete(table_name, schema, primary_keys)
  local where = get_where(primary_keys)
  local query = fmt("DELETE FROM %s WHERE %s RETURNING *",
                    table_name, where)
  local res, err = self:query(query, schema)
  if not res then return nil, err
  elseif res.affected_rows == 1 then
    return deserialize_timestamps(self, res[1], schema)
  end
end

--- Migrations
-- @section migrations

function _M:queries(queries)
  if utils.strip(queries) ~= "" then
    local res, err = self:query(queries)
    if not res then
      return err
    end
  end
end

function _M:drop_table(table_name)
  local res, err = self:query("DROP TABLE " .. table_name .. " CASCADE")
  if not res then
    return nil, err
  end
  return true
end

function _M:truncate_table(table_name)
  local res, err = self:query("TRUNCATE " .. table_name .. " CASCADE")
  if not res then
    return nil, err
  end
  return true
end

function _M:current_migrations()
  -- check if schema_migrations table exists
  local rows, err = self:query "SELECT to_regclass('schema_migrations')"
  if not rows then
    return nil, err
  end

  if #rows > 0 and rows[1].to_regclass == "schema_migrations" then
    return self:query "SELECT * FROM schema_migrations"
  else
    return {}
  end
end

function _M:record_migration(id, name)
  local res, err = self:query{
    [[
      CREATE OR REPLACE FUNCTION upsert_schema_migrations(identifier text, migration_name varchar) RETURNS VOID AS $$
      DECLARE
      BEGIN
          UPDATE schema_migrations SET migrations = array_append(migrations, migration_name) WHERE id = identifier;
          IF NOT FOUND THEN
          INSERT INTO schema_migrations(id, migrations) VALUES(identifier, ARRAY[migration_name]);
          END IF;
      END;
      $$ LANGUAGE 'plpgsql';
    ]],
    fmt("SELECT upsert_schema_migrations('%s', %s)", id, escape_literal(name))
  }
  if not res then
    return nil, err
  end
  return true
end

function _M:reachable()
  local conn_opts = query_opts(self)
  local pg = pgmoon.new(conn_opts)

  if conn_opts.timeout then
    pg:settimeout(conn_opts.timeout)
  end

  local ok, err = pg:connect()
  if not ok then
    return nil, Errors.db(err)
  end

  if conn_opts.socket_type == "nginx" then
    pg:keepalive()
  else
    pg:disconnect()
  end

  return true
end

return _M
