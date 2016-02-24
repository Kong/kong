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

-- Formatting

-- @see pgmoon
local function escape_identifier(ident)
  return '"'..(tostring(ident):gsub('"', '""'))..'"'
end

-- @see pgmoon
local function escape_literal(val, field)
  local t_val = type(val)
  if t_val == "number" then
    return tostring(val)
  elseif t_val == "string" then
    return "'"..tostring((val:gsub("'", "''"))).."'"
  elseif t_val == "boolean" then
    return val and "TRUE" or "FALSE"
  elseif t_val == "table" and field and field.type == "table" then
    local json = require "cjson"
    return escape_literal(json.encode(val))
  end
  error("don't know how to escape value: "..tostring(val))
end

local function get_where(tbl)
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
  elseif string.find(err_str, "violates foreign key constraint") then
    local col, value = string.match(err_str, "%((.+)%)=%((.+)%)")
    err = Errors.foreign {[col] = value}
  else
    err = Errors.db(err_str)
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

function PostgresDB:insert(table_name, schema, values)
  local cols, args = {}, {}
  for col, value in pairs(values) do
    cols[#cols + 1] = escape_identifier(col)
    args[#args + 1] = escape_literal(value, schema.fields[col])
  end

  cols = table.concat(cols, ", ")
  args = table.concat(args, ", ")

  local query = string.format("INSERT INTO %s(%s) VALUES(%s) RETURNING *",
                              table_name, cols, args)
  local res, err = self:query(query)
  if err then
    return nil, err
  elseif #res > 0 then
    return res[1]
  end
end

function PostgresDB:find(table_name, schema, primary_keys)
  local where = get_where(primary_keys)
  local query = get_select_query("*", table_name, where)
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
    where = get_where(tbl)
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
    where = get_where(tbl)
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
    where = get_where(tbl)
  end

  local query = get_select_query("COUNT(*)", table_name, where)
  local res, err =  self:query(query)
  if err then
    return nil, err
  elseif res and #res > 0 then
    return res[1].count
  end
end

function PostgresDB:update(table_name, schema, _, filter_keys, values, nils, full)
  local args = {}
  for col, value in pairs(values) do
    args[#args + 1] = string.format("%s = %s",
                      escape_identifier(col), escape_literal(value, schema.fields[col]))
  end

  if full then
    for col in pairs(nils) do
      args[#args + 1] = escape_identifier(col).." = NULL"
    end
  end

  args = table.concat(args, ", ")

  local where = get_where(filter_keys)
  local query = string.format("UPDATE %s SET %s WHERE %s RETURNING *",
                              table_name, args, where)
  local res, err = self:query(query)
  if err then
    return nil, err
  elseif res and res.affected_rows == 1 then
    return res[1]
  end
end

function PostgresDB:delete(table_name, schema, primary_keys)
  local where = get_where(primary_keys)
  local query = string.format("DELETE FROM %s WHERE %s RETURNING *",
                              table_name, where)
  local res, err = self:query(query)
  if err then
    return nil, err
  end

  if res and res.affected_rows == 1 then
    return res[1]
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
