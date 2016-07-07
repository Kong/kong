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
    protocol_options = {
      default_port = options.port
    },
    query_options = {
      prepare = true,
      consistency = cassandra.consistencies[options.consistency:lower()]
    },
    socket_options = {
      connect_timeout = options.timeout,
      read_timeout = options.timeout
    },
    ssl_options = {
      enabled = options.ssl.enabled,
      verify = options.ssl.verify,
      ca = options.ssl.certificate_authority
    }
  }

  if options.username and options.password then
    conn_opts.auth = cassandra.auth.PlainTextProvider(options.username, options.password)
  end

  CassandraDB.super.new(self, "cassandra", conn_opts)
end

function CassandraDB:infos()
  return {
    desc = "keyspace",
    name = self:_get_conn_options().keyspace
  }
end

-- Formatting

local function serialize_arg(field, value)
  if value == nil then
    return cassandra.unset
  elseif field.type == "id" then
    return cassandra.uuid(value)
  elseif field.type == "timestamp" then
    return cassandra.timestamp(value)
  elseif field.type == "table" or field.type == "array" then
    local json = require "cjson"
    return json.encode(value)
  else
    return value
  end
end

local function deserialize_rows(rows, schema)
  local json = require "cjson"
  for i, row in ipairs(rows) do
    for col, value in pairs(row) do
      if schema.fields[col].type == "table" or schema.fields[col].type == "array" then
        rows[i][col] = json.decode(value)
      end
    end
  end
end

local function get_where(schema, filter_keys, args)
  args = args or {}
  local fields = schema.fields
  local where = {}

  for col, value in pairs(filter_keys) do
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

local function check_unique_constraints(self, table_name, constraints, values, primary_keys, update)
  local errors

  for col, constraint in pairs(constraints.unique) do
    -- Only check constraints if value is non-null
    if values[col] ~= nil then
      local where, args = get_where(constraint.schema, {[col] = values[col]})
      local query = get_select_query(table_name, where)
      local rows, err = self:query(query, args, nil, constraint.schema)
      if err then
        return err
      elseif #rows > 0 then
        -- if in update, it's fine if the retrieved row is the same as the one updated
        if update then
          local same_row = true
          for col, val in pairs(primary_keys) do
            if val ~= rows[1][col] then
              same_row = false
              break
            end
          end

          if not same_row then
            errors = utils.add_error(errors, col, values[col])
          end
        else
          errors = utils.add_error(errors, col, values[col])
        end
      end
    end
  end

  return Errors.unique(errors)
end

local function check_foreign_constaints(self, values, constraints)
  local errors

  for col, constraint in pairs(constraints.foreign) do
    -- Only check foreign keys if value is non-null, if must not be null, field should be required
    if values[col] ~= nil then
      local res, err = self:find(constraint.table, constraint.schema, {[constraint.col] = values[col]})
      if err then
        return err
      elseif res == nil then
        errors = utils.add_error(errors, col, values[col])
      end
    end
  end

  return Errors.foreign(errors)
end

function CassandraDB:query(query, args, opts, schema, no_keyspace)
  CassandraDB.super.query(self, query, args)

  local conn_opts = self:_get_conn_options()
  if no_keyspace then
    conn_opts.keyspace = nil
  end
  local session, err = cassandra.spawn_session(conn_opts)
  if err then
    return nil, Errors.db(tostring(err))
  end

  local res, err = session:execute(query, args, opts)
  session:set_keep_alive()
  if err then
    return nil, Errors.db(tostring(err))
  end

  if schema ~= nil and res.type == "ROWS" then
    deserialize_rows(res, schema)
  end

  return res
end

function CassandraDB:insert(table_name, schema, model, constraints, options)
  local err = check_unique_constraints(self, table_name, constraints, model)
  if err then
    return nil, err
  end

  err = check_foreign_constaints(self, model, constraints)
  if err then
    return nil, err
  end

  local cols, binds, args = {}, {}, {}
  for col, value in pairs(model) do
    local field = schema.fields[col]
    cols[#cols + 1] = col
    args[#args + 1] = serialize_arg(field, value)
    binds[#binds + 1] = "?"
  end

  cols = table.concat(cols, ", ")
  binds = table.concat(binds, ", ")

  local query = string.format("INSERT INTO %s(%s) VALUES(%s)%s",
                              table_name, cols, binds, (options and options.ttl) and string.format(" USING TTL %d", options.ttl) or "")
  local err = select(2, self:query(query, args))
  if err then
    return nil, err
  end

  local primary_keys = model:extract_keys()

  local row, err = self:find(table_name, schema, primary_keys)
  if err then
    return nil, err
  end

  return row
end

function CassandraDB:find(table_name, schema, filter_keys)
  local where, args = get_where(schema, filter_keys)
  local query = get_select_query(table_name, where)
  local rows, err = self:query(query, args, nil, schema)
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
    where, args = get_where(schema, tbl)
  end

  local query = get_select_query(table_name, where)
  local res_rows, err = {}, nil

  for rows, page_err in session:execute(query, args, {auto_paging = true}) do
    if page_err then
      err = Errors.db(tostring(page_err))
      res_rows = nil
      break
    end
    if schema ~= nil then
      deserialize_rows(rows, schema)
    end
    for _, row in ipairs(rows) do
      res_rows[#res_rows + 1] = row
    end
  end

  session:set_keep_alive()

  return res_rows, err
end

function CassandraDB:find_page(table_name, tbl, paging_state, page_size, schema)
  local where, args
  if tbl ~= nil then
    where, args = get_where(schema, tbl)
  end

  local query = get_select_query(table_name, where)
  local rows, err = self:query(query, args, {page_size = page_size, paging_state = paging_state}, schema)
  if err then
    return nil, err
  elseif rows ~= nil then
    local paging_state
    if rows.meta and rows.meta.has_more_pages then
      paging_state = rows.meta.paging_state
    end
    rows.meta = nil
    rows.type = nil
    return rows, nil, paging_state
  end
end

function CassandraDB:count(table_name, tbl, schema)
  local where, args
  if tbl ~= nil then
    where, args = get_where(schema, tbl)
  end

  local query = get_select_query(table_name, where, "COUNT(*)")
  local res, err = self:query(query, args)
  if err then
    return nil, err
  elseif res and #res > 0 then
    return res[1].count
  end
end

function CassandraDB:update(table_name, schema, constraints, filter_keys, values, nils, full, model, options)
  -- must check unique constaints manually too
  local err = check_unique_constraints(self, table_name, constraints, values, filter_keys, true)
  if err then
    return nil, err
    end
  err = check_foreign_constaints(self, values, constraints)
  if err then
    return nil, err
  end

  -- Cassandra TTL on update is per-column and not per-row, and TTLs cannot be updated on primary keys.
  -- Not only that, but TTL on other rows can only be incremented, and not decremented. Because of all
  -- of these limitations, the only way to make this happen is to do an upsert operation.
  -- This implementation can be changed once Cassandra closes this issue: https://issues.apache.org/jira/browse/CASSANDRA-9312
  if options and options.ttl then
    if schema.primary_key and #schema.primary_key == 1 and filter_keys[schema.primary_key[1]] then
      local row, err = self:find(table_name, schema, filter_keys)
      if err then
        return nil, err
      elseif row then
        for k, v in pairs(row) do
          if not values[k] then
            model[k] = v -- Populate the model to be used later for the insert
          end
        end

        -- Insert without any contraint check, since the check has already been executed
        return self:insert(table_name, schema, model, {unique={}, foreign={}}, options)
      end
    else
      return nil, "Cannot update TTL on entities that have more than one primary_key"
    end
  end

  local sets, args, where = {}, {}
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

  where, args = get_where(schema, filter_keys, args)
  local query = string.format("UPDATE %s%s SET %s WHERE %s",
                              table_name, (options and options.ttl) and string.format(" USING TTL %d", options.ttl) or "", sets, where)
  local res, err = self:query(query, args)
  if err then
    return nil, err
  elseif res and res.type == "VOID" then
    return self:find(table_name, schema, filter_keys)
  end
end

local function cascade_delete(self, primary_keys, constraints)
  if constraints.cascade == nil then return end

  for f_entity, cascade in pairs(constraints.cascade) do
    local tbl = {[cascade.f_col] = primary_keys[cascade.col]}
    local rows, err = self:find_all(cascade.table, tbl, cascade.schema)
    if err then
      return nil, err
    end

    for _, row in ipairs(rows) do
      local primary_keys_to_delete = {}
      for _, primary_key in ipairs(cascade.schema.primary_key) do
        primary_keys_to_delete[primary_key] = row[primary_key]
      end

      local ok, err = self:delete(cascade.table, cascade.schema, primary_keys_to_delete)
      if not ok then
        return nil, err
      end
    end
  end
end

function CassandraDB:delete(table_name, schema, primary_keys, constraints)
  local row, err = self:find(table_name, schema, primary_keys)
  if err or row == nil then
    return nil, err
  end

  local where, args = get_where(schema, primary_keys)
  local query = string.format("DELETE FROM %s WHERE %s",
                              table_name, where)
  local res, err =  self:query(query, args)
  if err then
    return nil, err
  elseif res and res.type == "VOID" then
    if constraints ~= nil then
      cascade_delete(self, primary_keys, constraints)
    end
    return row
  end
end

-- Migrations

function CassandraDB:queries(queries, no_keyspace)
  for _, query in ipairs(utils.split(queries, ";")) do
    if utils.strip(query) ~= "" then
      local err = select(2, self:query(query, nil, nil, nil, no_keyspace))
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
  -- Check if keyspace exists
  local rows, err = self:query([[
    SELECT * FROM system.schema_keyspaces WHERE keyspace_name = ?
  ]], {self.options.keyspace}, nil, nil, true)
  if err then
    return nil, err
  elseif #rows == 0 then
    return {}
  end

  -- Check if schema_migrations table exists first
  rows, err = self:query([[
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
