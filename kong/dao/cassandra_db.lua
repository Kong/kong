local inspect = require "inspect"

local timestamp = require "kong.tools.timestamp"
local Errors = require "kong.dao.errors"
local BaseDB = require "kong.dao.base_db"
local utils = require "kong.tools.utils"
local uuid = require "lua_uuid"

local ngx_stub = _G.ngx
_G.ngx = nil
local cassandra = require "cassandra"
_G.ngx = ngx_stub

local CassandraDB = BaseDB:extend()

CassandraDB.dao_insert_values = {
  id = function()
    return uuid()
  end,
  timestamp = function()
    return timestamp.get_utc()
  end
}

function CassandraDB:new(options)
  local conn_opts = {
    shm = "cassandra",
    prepared_shm = "cassandra_prepared",
    contact_points = options.contact_points,
    keyspace = options.keyspace,
    query_options = {
      prepare = true
    },
    username = options.username,
    password = options.password,
    ssl_options = {
      enabled = options.ssl.enabled,
      verify = options.ssl.verify,
      ca = options.ssl.certificate_authority
    }
  }

  CassandraDB.super.new(self, "cassandra", conn_opts)
end

function CassandraDB:init_db()

end

-- Formatting

local function serialize_arg(field, value)
  if value == nil then
    return cassandra.unset
  elseif field.type == "id" then
    return cassandra.uuid(value)
  elseif field.type == "timestamp" then
    return cassandra.timestamp(value)
  else
    return value
  end
end

-- (%s, %s) VALUES(?, ?) / {arg1, arg2}
local function get_insert_columns_and_args(model)
  local fields = model.__schema.fields
  local cols, bind_args, args = {}, {}, {}

  for col, field in pairs(fields) do
    if model[col] ~= nil then
      local arg = serialize_arg(field, model[col])
      cols[#cols + 1] = col
      args[#args + 1] = arg
      bind_args[#bind_args + 1] = "?"
    end
  end

  return table.concat(cols, ", "), table.concat(bind_args, ", "), args
end

local function get_select_args_primary_keys(model)
  local schema = model.__schema
  local fields = schema.fields
  local where, args = {}, {}

  for _, col in ipairs(schema.primary_key) do
    if model[col] ~= nil then
      where[#where + 1] = col.." = ?"
      args[#args + 1] = serialize_arg(fields[col], model[col])
    end
  end

  if next(args) == nil then
    error("Missing PRIMARY KEY field", 3)
  end

  return table.concat(where, " AND "), args
end

local function get_select_args_primary_keys2(primary_keys, fields, args)
  args = args or {}
  local where = {}

  for col, value in pairs(primary_keys) do
    where[#where + 1] = col.." = ?"
    args[#args + 1] = serialize_arg(fields[col], value)
  end

  return table.concat(where, " AND "), args
end

local function get_select_args_custom(schema, tbl)
  local fields = schema.fields
  local where, args = {}, {}

  for col, value in pairs(tbl) do
    where[#where + 1] = col.." = ?"
    args[#args + 1] = serialize_arg(fields[col], value)
  end

  return table.concat(where, " AND "), args
end

local function get_select_query(table_name, where, select_clause)
  local query = string.format("SELECT %s FROM %s", select_clause or "*", table_name)
  if where ~= nil then
    query = query.." WHERE "..where.." ALLOW FILTERING"
  end

  return query
end

--- Querying

local function check_unique_constraints(self, model, update)
  local schema = model.__schema
  local errors

  for col, field in pairs(schema.fields) do
    if field.unique and model[col] ~= nil then
      local where, args = get_select_args_custom(model.__schema, {[col] = model[col]})
      local query = get_select_query(model.__table, where)
      local rows, err = self:query(query, args)
      if err then
        return err
      elseif #rows > 0 then
        -- if in update, it's fine if the retrieved row is the same as the one updated
        if update then
          local same_row = true
          for _, key in ipairs(schema.primary_key) do
            if model[key] ~= rows[1][key] then
              same_row = false
              break
            end
          end

          if not same_row then
            errors = utils.add_error(errors, col, model[col])
          end
        else
          errors = utils.add_error(errors, col, model[col])
        end
      end
    end
  end

  return Errors.unique(errors)
end

function CassandraDB:query(query, args, opts)
  CassandraDB.super.query(self, query, args)

  local conn_opts = self:_get_conn_options()
  local session, err = cassandra.spawn_session(conn_opts)
  if err then
    return nil, Errors.db(tostring(err))
  end

  local res, err = session:execute(query, args, opts)
  session:set_keep_alive()
  if err then
    return nil, Errors.db(tostring(err))
  end

  return res
end

function CassandraDB:insert(model)
  local err = check_unique_constraints(self, model)
  if err then
    return nil, err
  end

  local cols, binds, args = get_insert_columns_and_args(model)
  local query = string.format("INSERT INTO %s(%s) VALUES(%s)",
                              model.__table, cols, binds)
  local err = select(2, self:query(query, args))
  if err then
    return nil, err
  end

  local row, err = self:find(model)
  if err then
    return nil, err
  end

  return row
end

function CassandraDB:find(model)
  local where, args = get_select_args_primary_keys(model)
  local query = get_select_query(model.__table, where)
  local rows, err = self:query(query, args)
  if err then
    return nil, err
  elseif #rows > 0 then
    return rows[1]
  end
end

function CassandraDB:find_all(table_name, tbl, schema)
  local conn_opts = self:_get_conn_options()
  local session, err = cassandra.spawn_session(conn_opts)
  if err then
    return nil, Errors.db(tostring(err))
  end

  local where, args
  if tbl ~= nil then
    where, args = get_select_args_custom(schema, tbl)
  end

  local query = get_select_query(table_name, where)
  local res_rows, err = {}

  for rows, err in session:execute(query, args, {auto_paging = true}) do
    if err then
      err = Errors.db(tostring(err))
      res_rows = nil
      break
    end
    for _, row in ipairs(rows) do
      table.insert(res_rows, row)
    end
  end

  session:set_keep_alive()

  return res_rows, err
end

function CassandraDB:find_page(table_name, tbl, paging_state, page_size, schema)
  local where, args
  if tbl ~= nil then
    where, args = get_select_args_custom(schema, tbl)
  end

  local query = get_select_query(table_name, where)
  local rows, err = self:query(query, args, {page_size = page_size, paging_state = paging_state})
  if err then
    return nil, err
  elseif rows ~= nil then
    local paging_state
    if rows.meta and rows.meta.has_more_pages then
      paging_state = rows.meta.paging_state
    end
    rows.meta = nil
    return rows, nil, paging_state
  end
end

function CassandraDB:count(table_name, tbl, schema)
  local where, args
  if tbl ~= nil then
    where, args = get_select_args_custom(schema, tbl)
  end

  local query = get_select_query(table_name, where, "COUNT(*)")
  local res, err = self:query(query, args)
  if err then
    return nil, err
  elseif res and #res > 0 then
    return res[1].count
  end
end

function CassandraDB:update(model, full)
  -- row exists, must check manually
  local row, err = self:find(model)
  if err or row == nil then
    return nil, err
  end
  -- must check unique constaints manually too
  err = check_unique_constraints(self, model, true)
  if err then
    return nil, err
  end

  local schema = model.__schema
  local sets, args, where = {}, {}

  local primary_keys, values, nils = model:extract_keys()

  for col, value in pairs(values) do
    local field = schema.fields[col]
    sets[#sets + 1] = col.." = ?"
    args[#args + 1] = serialize_arg(field, value)
  end

  -- unset nil fields if asked for
  if full then
    for col in pairs(nils) do
      sets[#sets + 1] = col.." = ?"
      args[#args + 1] = cassandra.unset
    end
  end

  sets = table.concat(sets, ", ")

  where, args = get_select_args_primary_keys2(primary_keys, schema.fields, args)
  local query = string.format("UPDATE %s SET %s WHERE %s",
                              model.__table, sets, where)
  --print(query)
  --print(inspect(args))
  local res, err = self:query(query, args)
  if err then
    return nil, err
  elseif res and res.type == "VOID" then
    return self:find(model)
  end
end

-- Migrations

function CassandraDB:queries(queries)
  for _, query in ipairs(utils.split(queries, ";")) do
    if utils.strip(query) ~= "" then
      local err = select(2, self:query(query))
      if err then
        return err
      end
    end
  end
end

function CassandraDB:drop_table(table_name)
  return select(2, self:query("DROP TABLE "..table_name))
end

function CassandraDB:truncate_table(table_name)
  return select(2, self:query("TRUNCATE "..table_name))
end

function CassandraDB:current_migrations()
  -- Check if schema_migrations table exists first
  local rows, err = self:query([[
    SELECT COUNT(*) FROM system.schema_columnfamilies
    WHERE keyspace_name = ? AND columnfamily_name = ?
  ]], {
    self.options.keyspace,
    "schema_migrations"
  })
  if err then
    return nil, err
  end

  if rows[1].count > 0 then
    return self:query "SELECT * FROM schema_migrations"
  else
    return {}
  end
end

function CassandraDB:record_migration(id, name)
  return select(2, self:query([[
    UPDATE schema_migrations SET migrations = migrations + ? WHERE id = ?
  ]], {
    cassandra.list {name},
    id
  }))
end

return CassandraDB
