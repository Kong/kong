-- Copyright (C) Mashape, Inc.

local cassandra = require "cassandra"
local dao_utils = require "apenode.dao.dao_utils"
local stringy = require "stringy"
local Object = require "classic"
local utils = require "apenode.tools.utils"
local uuid = require "uuid"

-- This is important to seed the UUID generator
uuid.seed()

local BaseDao = Object:extend()

function BaseDao:new(database, collection, schema, properties)
  self._db = database
  self._schema = schema
  self._collection = collection
  self._properties = properties

  -- Cache the prepared statements if already prepared
  self._stmt_cache = {}
end

-- Insert an entity
-- @param table entity Entity to insert or replace
-- @return table Inserted entity with its id property
-- @return table Error if error
function BaseDao:insert(entity)
  if entity then
    entity = dao_utils.serialize(self._schema, entity)
  else
    return nil
  end

  -- Set an UUID as the ID of the entity
  if not entity.id then
    entity.id = uuid()
  end

  local query, values_to_bind = self:build_insert_query(entity)
  local result, err = self:_exec_stmt(query, values_to_bind)

  if err then
    return nil, err
  else
    return entity
  end
end

-- Update one or many entities according to a WHERE statement
-- @param table entity Entity to update
-- @return table Updated entity
-- @return table Error if error
function BaseDao:update_by_id(entity)
  if entity and utils.table_size(entity) > 0 then
    entity = dao_utils.serialize(self._schema, entity)
  else
    return 0
  end

  local query, values_to_bind = self:build_udpdate_query(entity)

  -- Last '?' placeholder is the WHERE id = ?
  table.insert(values_to_bind, cassandra.uuid(entity.id))

  local res, err = self:_exec_stmt(query, values_to_bind)
  if err then
    return 0, err
  else
    return 1
  end
end

-- Find one row according to a condition determined by the keys
-- @param table where_keys Keys used to build a WHERE condition
-- @return table Retrieved row or nil
-- @return table Error if error
function BaseDao:find_one(where_keys)
  local data, total, err = self:find(where_keys, 1, 1)

  -- TODO this is a hack for cassandra
  local result = nil
  if total > 0 then
    result = data[1]
  end

  return result, err
end

-- Find rows according to a WHERE condition determined by the passed keys
-- @param table (Optional) where_keys Keys used to build a WHERE condition
-- @return table Retrieved rows or empty list
-- @return number Total count of entities matching the SELECT
-- @return table Error if error during execution
function BaseDao:find(where_keys)
  where_keys = dao_utils.serialize(self._schema, where_keys)

  local _, _, values_to_bind = self:_build_query_args(where_keys)

  -- Build SELECT and COUNT queries
  local query = self:build_select_query(where_keys)
  local count_query = self:build_count_query(where_keys)

  -- Execute SELECT query
  local results, err = self:_exec_stmt(query, values_to_bind)
  if err then
    return nil, 0, err
  end

  -- Execute COUNT query
  local count, err = self:_exec_stmt(count_query, values_to_bind)
  if count == nil then
    return nil, 0, err
  end

  local count_value = table.remove(count, 1).count

  -- Deserialization
  for _,result in ipairs(results) do
    result = dao_utils.deserialize(self._schema, result)
    for k,_ in pairs(result) do -- Remove unexisting fields
      if not self._schema[k] then
        result[k] = nil
      end
    end
  end

  return results, count_value
end

-- Delete row(s) according to a WHERE condition determined by the passed keys
-- @param table where_keys Keys used to build a WHERE condition
-- @return {boolean} Success of the query
-- @return {table} Error if error
function BaseDao:delete_by_id(id)
  if not id then
    return false, { message = "Cannot delete an entire collection" }
  end

  -- Check if exists before delete
  local exists, err = self:find_one { id = id }
  if not exists or err then
    return false, err
  end

  local query = self:build_delete_query { id = id }
  return self:_exec_stmt(query, { cassandra.uuid(id) })
end

-----------------
-- QUERY UTILS --
-----------------

-- Build a SELECT query on the current collection and model schema
-- with a WHERE condition
-- @param table where_keys Selector for the row to select
-- @return string The computed SELECT query with palceholders to be binded
function BaseDao:build_select_query(where_keys)
  local where = BaseDao._build_where_fields(where_keys)
  return [[ SELECT * FROM ]]..self._collection..where
end

-- Build a SELECT COUNT(*) query
-- @param table where_keys Selector for the count to select
-- @return string A SELECT COUNT(*) query with palceholders to be binded
function BaseDao:build_count_query(where_keys)
  local where = BaseDao._build_where_fields(where_keys)
  return [[ SELECT COUNT(*) FROM ]]..self._collection..where
end

-- Build a DELETE FROM query
-- @param table where_keys Selector for the count to select
-- @return string A DELETE query with palceholders to be binded
function BaseDao:build_delete_query(where_keys)
  local where = BaseDao._build_where_fields(where_keys)
  return [[ DELETE FROM ]]..self._collection..where
end

-- Build a INSERT INTO query
-- @param table entity An entity with keys representing the columns of the table
-- @return string An INSERT INTO query with palceholders to be binded
function BaseDao:build_insert_query(entity)
  local columns, placeholders, values_to_bind = self:_build_query_args(entity)
  return [[ INSERT INTO ]]..self._collection..[[ ( ]]..table.concat(columns, ",")..[[ )
              VALUES ( ]]..table.concat(placeholders, ",")..[[ ) ]], values_to_bind
end

-- Build an UPDATE query
-- @param table entity An entity with keys representing the columns of the table
-- @param table where_keys Selector for the entity to update
-- @return string An UPDATE query with palceholders to be binded
function BaseDao:build_udpdate_query(entity, where_keys)
  if where_keys == nil then where_keys = { id = "" } end

  local columns, placeholders, values_to_bind = self:_build_query_args(entity, true)
  local where = BaseDao._build_where_fields(where_keys)

  local update_placeholders = {}
  for _,column in ipairs(columns) do
    table.insert(update_placeholders, column.."=?")
  end

  return [[ UPDATE ]]..self._collection..[[ SET ]]..table.concat(update_placeholders, ",")..where, values_to_bind
end

-- Utility function to create query placeholders, values to bind from an entity
--
-- Cassandra needs special values for uuids and timestamps values in a command (cassandra.uuid() or cassandra.timestamp())
--
-- @param table entity The entity whose fields needs to be parsed
-- @param boolean update
-- @return string A list of column names
-- @return string A list of values placeholders parameters
-- @return string A list of actual values to bind to the placeholders
function BaseDao:_build_query_args(entity, update)
  -- Columns, "?,?,?"
  local columns, placeholders, values_to_bind = {}, {}, {}

  if update then
    for k, v in pairs(entity) do
      local schema_field = self._schema[k]
      if schema_field.type ~= "id" and schema_field.type ~= "timestamp" then
        table.insert(columns, k)
        table.insert(placeholders, "?")
        table.insert(values_to_bind, v)
      end
    end
    return columns, placeholders, values_to_bind
  end

  for k, v in pairs(entity) do
    local schema_field = self._schema[k]

    table.insert(columns, k)
    table.insert(placeholders, "?")

    -- Build values to bind with special cassandra values on uuids and timestamps
    if not update and schema_field.type == "id" then
      table.insert(values_to_bind, cassandra.uuid(v))
    elseif not update and schema_field.type == "timestamp" then
      local created_at = v
      if string.len(tostring(created_at)) == 10 then
        created_at = created_at * 1000 -- Convert to milliseconds
      end
      table.insert(values_to_bind, cassandra.timestamp(created_at))
    else
      table.insert(values_to_bind, v)
    end
  end

  return columns, placeholders, values_to_bind
end

-- Build a WHERE statement from keys of a table
-- If the passed table is nil or empty, we return a space,
-- so all our query utils don't have to do supplementary checks
-- to know if the WHERE statement is empty or not.
-- Ex:
--  { public_dns = "host.com" } returns: WHERE public_dns = ?
--
-- @param t The table for which each key should be in the WHERE clause
-- @return string A list of fields for the WHERE clause
function BaseDao._build_where_fields(t)
  if t == nil or utils.table_size(t) == 0 then return " " end

  local result = {}
  for k,v in pairs(t) do
    table.insert(result, k.."=?")
  end

  return [[ WHERE ]]..table.concat(result, " AND ")
end

---------------------
-- Cassandra UTILS --
---------------------

-- Execute a query or prepared statement.

-- Will connect to Cassandra, set the keyspace,
-- look into the memory cache if the query is prepared, or prepare it otherwise,
-- execute the statement and finally put the connection in the nginx pool
--
-- Will throw an error if the statement cannot be prepared.
--
-- @param {string} query A CQL query
-- @param {table} values Values to bind to the query
-- @return {boolean} Success of the query
-- @return {table} Error during connection or execution
function BaseDao:_exec_stmt(query, values)
  -- Connects to Cassandra
  local session = cassandra.new()
  session:set_timeout(self._properties.timeout)

  --local connected, err = self._db:connect(self._properties.host, self._properties.port)
  local connected, err = session:connect(self._properties.host, self._properties.port)
  if not connected then
    return false, err
  end

  -- Set apenode keyspace
  --local ok, err = self._db:set_keyspace(self._properties.keyspace)
  local ok, err = session:set_keyspace(self._properties.keyspace)
  if not ok then
    return false, err
  end

  -- Retrieve statement if exists in cache or creates it
  --local statement, err = self._db:prepare(query)
  local statement, err = session:prepare(query)
  if not statement then
    error("Failed to prepare statement: "..err)
  end

  -- Execute statement
  --local result, err = self._db:execute(statement, values)
  local success, err = session:execute(statement, values)
  if err then
    return false, err
  end

  -- Puts back the connection in the nginx pool
  local ok, err = session:set_keepalive(self._properties.keepalive)
  if not ok and err ~= "luasocket does not support reusable sockets" then
    return false, err
  else
    return success
  end
end

return BaseDao
