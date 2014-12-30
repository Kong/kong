-- Copyright (C) Mashape, Inc.

local cassandra = require "cassandra"
local utils = require "apenode.utils"
local dao_utils = require "apenode.dao.dao_utils"
local Object = require "classic"
local uuid = require "uuid"
local inspect = require "inspect"

-- This is important to seed the UUID generator
uuid.seed()

local BaseDao = Object:extend()

function BaseDao:new(configuration, collection, schema)
  self._configuration = configuration
  self._collection = collection
  self._schema = schema

  -- Cache the prepared statements if already prepared
  self._stmt_cache = {}
end

-- Utility function to create query fields and values from an entity, useful for save and update
-- @param entity The entity whose fields needs to be parsed
-- @return A list of fields, of values placeholders, and the actual values table
local function get_cmd_args(entity, update)
  local cmd_field_values = {}
  local cmd_fields = {}
  local cmd_values = {}

  if update then
    entity.id = nil
    entity.created_at = nil
  end

  for k, v in pairs(entity) do
    table.insert(cmd_fields, k)
    table.insert(cmd_values, "?")
    if type(v) == "table" then
      table.insert(cmd_field_values, cassandra.list(v))
    elseif k == "id" then
      table.insert(cmd_field_values, cassandra.uuid(v))
    elseif k == "created_at" then
      local _created_at = v
      if string.len(tostring(_created_at)) == 10 then
        _created_at = _created_at * 1000 -- Convert to milliseconds
      end
      table.insert(cmd_field_values, cassandra.timestamp(_created_at))
    else
      table.insert(cmd_field_values, v)
    end
  end

  return table.concat(cmd_fields, ","), table.concat(cmd_values, ","), cmd_field_values
end

-- Insert an entity
-- @param table entity Entity to insert
-- @return table Inserted entity with its rowid property
-- @return table Error if error
function BaseDao:insert(entity)
  if entity then
    entity = dao_utils.serialize(self._schema, entity)
  else
    return nil
  end

  -- Set an UUID as the ID of the entity
  entity.id = uuid()

  -- Prepare the command
  local cmd_fields, cmd_values, cmd_field_values = get_cmd_args(entity, false)

  -- Execute the command
  local cmd = "INSERT INTO " .. self._collection .. " (" .. cmd_fields .. ") VALUES (" .. cmd_values .. ")"

  local result, err = self:_query(cmd, cmd_field_values)
  return entity
end

-- Update one or many entities according to a WHERE statement
-- @param table entity Entity to update
-- @return table Updated entity
-- @return table Error if error
function BaseDao:update(entity, where_keys)
  if entity then
    entity = dao_utils.serialize(self._schema, entity)
  else
    return nil
  end

  -- Remove duplicated values between entity and where_keys
  -- it would be incorrect to have:
  -- entity { id = 1 } and where_keys { id = "none" }
  -- 1 would be binded in the statement for the WHERE clause instead of "none"
  for k,_ in pairs(entity) do
    if where_keys and where_keys[k] then
      entity[k] = where_keys[k]
    end
  end

  local query = self:build_udpate_query(entity, where_keys)
  local stmt = self:get_statement(query)
  stmt:bind_names(entity)

  return self:exec_stmt_count_rows(stmt)
end

-- Insert or update an entity
-- @param table entity Entity to insert or replace
-- @param table where_keys Selector for the row to insert or update
-- @return table Inserted/updated entity with its rowid property
-- @return table Error if error
function BaseDao:insert_or_update(entity, where_keys)
  if entity then
    entity = dao_utils.serialize(self._schema, entity)
  else
    return nil
  end

  local query = self:build_insert_or_update_query(entity, where_keys)
  local stmt = self:get_statement(query)
  stmt:bind_names(entity)

  local rowid, err = self:exec_stmt_rowid(stmt)
  if err then
    return nil, err
  end

  entity.id = rowid

  return entity
end

-- Find one row according to a condition determined by the keys
-- @param table where_keys Keys used to build a WHERE condition
-- @return table Retrieved row or nil
-- @return table Error if error
function BaseDao:find_one(where_keys)
  local data, total, err = self:find(where_keys, 1, 1)
  local result = nil
  if total > 0 then
    result = data[1]
  end
  return result, err
end

-- Find rows according to a WHERE condition determined by the passed keys
-- @param table (optional) where_keys Keys used to build a WHERE condition
-- @param number page Page to retrieve (default: 1)
-- @param number size Size of the page (default = 30, max = 100)
-- @return table Retrieved rows or empty list
-- @return number Total count of entities matching the SELECT
-- @return table Error if error
function BaseDao:find(where_keys, page, size)
  -- where_keys is optional
  if type(where_keys) ~= "table" then
    size = page
    page = where_keys
    where_keys = nil
  end

  where_keys = dao_utils.serialize(self._schema, where_keys)

  -- Pagination
  if not page then page = 1 end
  if not size then size = 30 end
  size = math.min(size, 100)
  local start_offset = ((page - 1) * size)

  local query = self:build_select_query(where_keys, true)
  local count_query = self:build_count_query(where_keys)
  local stmt = self:get_statement(query)
  local count_stmt = self:get_statement(count_query)

  -- Build binding table
  local values_to_bind = {}
  if where_keys then
    values_to_bind = where_keys
  end

  values_to_bind.page = start_offset
  values_to_bind.size = size

  stmt:bind_names(values_to_bind)
  count_stmt:bind_names(values_to_bind)

  -- Statements execution
  local results, err = self:exec_select_stmt(stmt)
  if err then
    return nil, nil, err
  end

  local count_result, err = self:exec_stmt_rowid(count_stmt)
  if err then
    return nil, nil, err
  end

  -- Deserialization
  for _,result in ipairs(results) do
    result = dao_utils.deserialize(self._schema, result)
  end

  return results, count_result
end

-- Delete row(s) according to a WHERE condition determined by the passed keys
-- @param table where_keys Keys used to build a WHERE condition
-- @return number Number of rows affected by the executed query
-- @return table Error if error
function BaseDao:delete(where_keys)
  where_keys = dao_utils.serialize(self._schema, where_keys)

  if not where_keys or  utils.table_size(where_keys) == 0 then
    return nil, { message = "Cannot delete an entire collection" }
  end

  local query = self:build_delete_query(where_keys)
  local stmt = self:get_statement(query)

  -- Build binding table
  stmt:bind_names(where_keys)

  return self:exec_stmt_count_rows(stmt)
end

-----------------
-- QUERY UTILS --
-----------------

-- Utility function to execute queries
-- @param cmd The CQL command to execute
-- @param args The arguments of the command
-- @return the result of the operation
function BaseDao:_query(cmd, args)
  -- Creates a new session
  local session = cassandra.new()

  -- Sets the timeout for the subsequent operations
  session:set_timeout(self._configuration.timeout)

  -- Connects to Cassandra
  local connected, err = session:connect(self._configuration.host, self._configuration.port)
  if not connected then
    return nil, err
  end

  -- Sets the default keyspace
  local ok, err = session:set_keyspace(self._configuration.keyspace)
  if not ok then
    return nil, err
  end

  local stmt = self._stmt_cache[cmd]
  if not stmt then
    local new_stmt, err = session:prepare(cmd)
    if err then
      return nil, err
    end
    self._stmt_cache[cmd] = new_stmt
    stmt = new_stmt
  end

  -- Executes the command
  local result, err = session:execute(stmt, args)
  if err then
    return nil, err
  end

  -- Puts back the connection in the nginx pool
  local ok, err = session:set_keepalive(self._configuration.keepalive)
  if not ok then
    return nil, err
  end

  return result
end

return BaseDao
