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

function BaseDao:new(database, collection, schema)
  self._db = database
  self._schema = schema
  self._collection = collection

  -- Cache the prepared statements if already prepared
  self._stmt_cache = {}
end

-- Finalize the cached prepared statements
function BaseDao:finalize()
  -- No finalize statements for openresty-cassandra
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
  if not entity.id then
    entity.id = uuid()
  end

  local query = self:build_insert_query(entity)
  local result, err = self._client:query(cmd, values_to_bind)

  if err then
    return nil, err
  end

  return entity
end

-- Update one or many entities according to a WHERE statement
-- @param table entity Entity to update
-- @return table Updated entity
-- @return table Error if error
function BaseDao:update(entity)
  if entity and utils.table_size(entity) > 0 then
    entity = dao_utils.serialize(self._schema, entity)
  else
    return 0
  end

  -- Only support id as a selector
  local where_keys = {
    id = entity.id
  }

  if entity.id ~= nil then
    entity.id = nil
  end

  local query, values_to_bind = self:build_udpdate_query(entity, where_keys)

  -- Last '?' placeholder is the WHERE id = ?
  table.insert(values_to_bind, cassandra.uuid(entity.id))

  return self._client:query(cmd, values_to_bind)
end

-- Insert or update an entity
-- @param table entity Entity to insert or replace
-- @param table where_keys Selector for the row to insert or update
-- @return table Inserted/updated entity with its rowid property
-- @return table Error if error
function BaseDao:insert_or_update(entity, where_keys)
  return self:insert(entity) -- In Cassandra inserts are upserts
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
-- @param table (optional) where_keys Keys used to build a WHERE condition
-- @param number page Page to retrieve (default: 1)
-- @param number size Size of the page (default = 30, max = 100)
-- @return table Retrieved rows or empty list
-- @return number Total count of entities matching the SELECT
-- @return table Error if error during execution
function BaseDao:find(where_keys, page, size)
  -- where_keys is optional
  if type(where_keys) ~= "table" then
    size = page
    page = where_keys
    where_keys = nil
  end

  where_keys = dao_utils.serialize(self._schema, where_keys)

  local _, _, values_to_bind = BaseDao._build_query_args(where_keys)

  -- Build SELECT and COUNT queries
  local query = self:build_select_query(where_keys)
  local count_query = self:build_count_query(where_keys)

  -- Execute SELECT query
  local results, err = self._client:query(query, values_to_bind)
  if err then
    return nil, nil, err
  end

  -- Execute COUNT query
  local count, err = self._client:query(count_query, values_to_bind)
  if count == nil then
    return nil, nil, err
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
-- @return number Number of rows affected by the executed query
-- @return table Error if error
function BaseDao:delete_by_id(id)
  local query = self:build_delete_query({ id = id })

  -- Execute the command
  local results, err = self._client:query(query, { cassandra.uuid(id) })
  if not results then
    return nil, err
  end

  -- TODO This is another trick for cassandra
  return 1
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
  local columns, placeholders = BaseDao._build_query_args(entity)
  return [[ INSERT INTO ]]..self._collection..[[ ( ]]..table.concat(columns, ",")..[[ ) VALUES ( ]]..placeholders
end

-- Build an UPDATE query
-- @param table entity An entity with keys representing the columns of the table
-- @param table where_keys Selector for the entity to update
-- @return string An UPDATE query with palceholders to be binded
function BaseDao:build_udpdate_query(entity, where_keys)
  local columns, placeholders, values_to_bind = BaseDao._build_query_args(entity, true)
  local where = BaseDao._build_where_fields(where_keys)

  local update_placeholders = {}
  for _,column in ipairs(columns) do
    table.insert(update_placeholders, column.."=?")
  end

  return [[ UPDATE ]]..self._collection..[[ SET ]]..table.concat(update_placeholders, ",")..where, values_to_bind
end

-- Utility function to create query fields and values from an entity
--
-- Cassandra needs special values for uuids and timestamps values in a command (cassandra.uuid() or cassandra.timestamp())
--
-- @param table entity The entity whose fields needs to be parsed
-- @param boolean update
-- @return string A list of column names
-- @return string A list of values placeholders parameters
-- @return string A list of actual values to bind to the placeholders
function BaseDao._build_query_args(entity, update)
  -- Columns, "?,?,?"
  local columns, placeholders, values_to_bind = {}, {}, {}

  if update then
    entity.id = nil
    entity.created_at = nil
  end

  for k, v in pairs(entity) do
    table.insert(columns, k)
    table.insert(placeholders, "?")

    -- Values to bind
    if type(v) == "table" then
      table.insert(values_to_bind, cassandra.list(v))
    elseif k == "created_at" or k == "timestamp" then
      local created_at = v
      if string.len(tostring(created_at)) == 10 then
        created_at = created_at * 1000 -- Convert to milliseconds
      end
      table.insert(values_to_bind, cassandra.timestamp(created_at))
    elseif stringy.endswith(k, "id") then
      table.insert(values_to_bind, cassandra.uuid(v))
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
  for k_,v in pairs(entity) do
    table.insert(result, v.."=?")
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
-- @param string query A CQL query
-- @param table args Values to bind to the query
-- @return table Result(s) of the query
-- @return table Error during connection or execution
function BaseDao:_exec_stmt(query, args)
  -- Connects to Cassandra
  local connected, err = session:connect(self._properties.host, self._properties.port)
  if not connected then
    return nil, err
  end

  -- Set apenode keyspace
  local ok, err = session:set_keyspace(self._properties.keyspace)
  if not ok then
    return nil, err
  end

  -- Retrieve statement if exists in cache or creates it
  local statement, err = session:prepare(query)
  if not statement then
    error("Failed to prepare statement: "..err)
  end

  -- Execute statement
  local result, err = self._db.execute(statement)
  if err then
    return nil, err
  end

  -- Puts back the connection in the nginx pool
  local ok, err = session:set_keepalive(self._properties.keepalive)
  if not ok and err ~= "luasocket does not support reusable sockets" then
    return nil, err
  end

  return result
end

return BaseDao
