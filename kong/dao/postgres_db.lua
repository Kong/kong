local inspect = require "inspect"

local BaseDB = require "kong.dao.base_db"
local Errors = require "kong.dao.errors"
local uuid = require "lua_uuid"

local ngx_stub = _G.ngx
_G.ngx = nil
local pgmoon = require "pgmoon"
_G.ngx = ngx_stub

local PostgresDB = BaseDB:extend()

PostgresDB.dao_insert_values = {
  id = function()
    return uuid()
  end
}

function PostgresDB:new(...)
  PostgresDB.super.new(self, "postgres", ...)
end

function PostgresDB:init_db()

end

-- Formatting

-- @see pgmoon
local function escape_identifier(ident)
  return '"'..(tostring(ident):gsub('"', '""'))..'"'
end

-- @see pgmoon
local function escape_literal(val)
  local t_val = type(val)
  if t_val == "number" then
    return tostring(val)
  elseif t_val == "string" then
    return "'"..tostring((val:gsub("'", "''"))).."'"
  elseif t_val == "boolean" then
    return val and "TRUE" or "FALSE"
  end
  error("don't know how to escape value: "..tostring(val))
end

local function get_insert_columns_and_args(tbl)
  local cols, args = {}, {}
  for col, value in pairs(tbl) do
    cols[#cols + 1] = escape_identifier(col)
    args[#args + 1] = escape_literal(value)
  end
  return table.concat(cols, ", "), table.concat(args, ", ")
end

local function get_select_args_primary_keys(model)
  local schema = model.__schema
  local fields = schema.fields
  local where = {}

  for _, col in ipairs(schema.primary_key) do
    if model[col] ~= nil then
      where[#where + 1] = string.format("%s = %s",
                          escape_identifier(col),
                          escape_literal(model[col]))
    end
  end

  if next(where) == nil then
    error("Missing PRIMARY KEY field", 3)
  end

  return table.concat(where, " AND ")
end

local function get_select_args_custom(tbl)
  local where = {}

  for col, value in pairs(tbl) do
    where[#where + 1] = string.format("%s = %s",
                        escape_identifier(col),
                        escape_literal(value))
  end

  return table.concat(where, " AND ")
end

local function parse_error(err_str)
  local err
  if string.find(err_str, "Key .* already exists") then
    local col, value = string.match(err_str, "%((.+)%)=%((.+)%)")
    err = Errors.unique {[col] = value}
  else
    err = Errors.db(err)
  end

  return err
end

local function get_select_query(select_clause, table, where, offset, limit)
  local query = string.format("SELECT %s FROM %s", select_clause, table)
  if where ~= nil then
    query = query.." WHERE "..where
  end
  if limit ~= nil then
    query = query.." LIMIT "..limit
  end
  if offset ~= nil and offset > 0 then
    query = query.." OFFSET "..offset
  end
  return query
end

-- Querying

function PostgresDB:query(...)
  PostgresDB.super.query(self, ...)

  local pg = pgmoon.new(self:_get_conn_options())
  local ok, err = pg:connect()
  if not ok then
    return nil, Errors.db(err)
  end

  local res, err = pg:query(...)
  if ngx and ngx.get_phase() ~= "init" then
    pg:keepalive()
  else
    pg:disconnect()
  end

  if res == nil then
    return nil, parse_error(err)
  end

  return res
end

function PostgresDB:insert(model)
  local cols, args = get_insert_columns_and_args(model)
  local query = string.format("INSERT INTO %s(%s) VALUES(%s) RETURNING *",
                              model.__table,
                              cols,
                              args)
  local res, err = self:query(query)
  if err then
    return nil, err
  elseif #res > 0 then
    return res[1]
  end
end

function PostgresDB:find(model)
  local where = get_select_args_primary_keys(model)
  local query = get_select_query("*", model.__table, where)
  local rows, err = self:query(query)
  if err then
    return nil, err
  elseif rows and #rows > 0 then
    return rows[1]
  end
end

function PostgresDB:find_all(table_name, tbl)
  local where
  if tbl ~= nil then
    where = get_select_args_custom(tbl)
  end

  local query = get_select_query("*", table_name, where)
  return self:query(query)
end

function PostgresDB:find_page(table_name, tbl, page, page_size)
  if page == nil then
    page = 1
  end

  local total_count, err = self:count(table_name, tbl)
  if err then
    return nil, err
  end

  local total_pages = math.ceil(total_count/page_size)
  local offset = page_size * (page - 1)

  local where
  if tbl ~= nil then
    where = get_select_args_custom(tbl)
  end

  local query = get_select_query("*", table_name, where, offset, page_size)
  local rows, err = self:query(query)
  if err then
    return nil, err
  end

  local next_page = page + 1
  return rows, nil, (next_page <= total_pages and next_page or nil)
end

function PostgresDB:count(table_name, tbl)
  local where
  if tbl ~= nil then
    where = get_select_args_custom(tbl)
  end

  local query = get_select_query("COUNT(*)", table_name, where, page_size, page_offset)
  local res, err =  self:query(query)
  if err then
    return nil, err
  elseif res and #res > 0 then
    return res[1].count
  end
end

-- Migrations

function PostgresDB:queries(queries)
  return select(2, self:query(queries))
end

function PostgresDB:drop_table(table_name)
  return select(2, self:query("DROP TABLE "..table_name))
end

function PostgresDB:truncate_table(table_name)
  return select(2, self:query("TRUNCATE "..table_name.." CASCADE"))
end

function PostgresDB:current_migrations()
  -- Check if schema_migrations table exists
  local rows, err = self:query "SELECT to_regclass('public.schema_migrations')"
  if err then
    return nil, err
  end

  if #rows > 0 and rows[1].to_regclass == "schema_migrations" then
    return self:query "SELECT * FROM schema_migrations"
  else
    return {}
  end
end

function PostgresDB:record_migration(id, name)
  return select(2, self:query {
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
    string.format("SELECT upsert_schema_migrations('%s', %s)", id, escape_literal(name))
  })
end

return PostgresDB
