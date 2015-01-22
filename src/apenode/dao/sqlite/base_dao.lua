-- Copyright (C) Mashape, Inc.

local dao_utils = require "apenode.dao.dao_utils"
local Object = require "classic"
local utils = require "apenode.tools.utils"

local BaseDao = Object:extend()

function BaseDao:new(database, collection, schema)
  self._db = database
  self._schema = schema
  self._collection = collection

  -- Cache the prepared statemements
  self._stmt_cache = {}
end

-- Finalize the cached prepared statements
function BaseDao:finalize()
  for _, statement in pairs(self._stmt_cache) do
    statement:finalize()
  end
end

-- Update one or many entities according to a WHERE statement
-- @param table entity Entity to update
-- @param table where_keys Selector for what entity to update
-- @return table Updated entity
-- @return table Error if error
function BaseDao:update(entity)
  if entity then
    entity = dao_utils.serialize(self._schema, entity)
  else
    return 0
  end

  -- Only support id as a selector
  local where_keys = {
    id = entity.id
  }

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
function BaseDao:delete_by_id(id)
  where_keys = dao_utils.serialize(self._schema, { id = id})

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

-- Return a cached prepared statement if present, create one if not present
-- @param query The query to execute, used as key to retrieve the cached statement
-- @return sqlite3 prepared statement
function BaseDao:get_statement(query)
  local statement = self._stmt_cache[query]
  if statement then
    return statement
  else
    statement = self._db:prepare(query)
    if not statement then
      error("SQLite Error. Failed to prepare statement: "..self._db:errmsg().."\n"..query)
    else
      self._stmt_cache[query] = statement
      return statement
    end
  end
end

-- Build a SELECT query on the current collection and model schema
-- with a WHERE condition
-- @param table where_keys Selector for the row to select
-- @param boolean paginated Indicates if the request needs a LIMIT :page[, :size]
-- @return string The computed SELECT query to be binded
function BaseDao:build_select_query(where_keys, paginated)
  local where = self:build_where_fields(where_keys)
  local query = [[ SELECT * FROM ]]..self._collection..where..[[ LIMIT :page ]]

  if paginated then
    query = query..[[, :size]]
  end

  return query
end

-- Build a SELECT COUNT(*) query
-- @param table where_keys Selector for the count to select
-- @return string A SELECT COUNT(*) query to be binded
function BaseDao:build_count_query(where_keys)
  local where = self:build_where_fields(where_keys)

  return [[ SELECT COUNT(*) FROM ]]..self._collection..where
end

-- Build an UPDATE query
-- @param table entity Object with keys that will be in the prepared statement
-- @return string An UPDATE query to be binded
function BaseDao:build_udpate_query(entity, where_keys)
  if where_keys == nil then where_keys = { id = "" } end

  local fields = {}
  local where = self:build_where_fields(where_keys)

  -- Build the VALUES to insert
  for k,_ in pairs(entity) do
    table.insert(fields, k.."=:"..k)
  end

  return [[ UPDATE ]]..self._collection..[[ SET ]]..table.concat(fields, ",")..where
end

-- Allows to insert or update if already existing a row on the current collection
-- from a WHERE condition with an INSERT OR REPLACE query.
--
-- Ex:
-- build_insert_or_update_query({ name = "hello", host = "mashape.com" }, { "id" = 1 })

-- returns: INSERT OR REPLACE INTO apis(:name, :host, :target)
--          VALUES(?,
--                 ?,
--                 (SELECT target FROM apis WHERE id = :id))
--
-- @param table entity Entity to insert or update on the current collection
-- @param table where_keys Selector for the row to insert or update
-- @return string The computed INSERT OR REPLACE query to be binded
function BaseDao:build_insert_or_update_query(entity, where_keys)
  if where_keys == nil then where_keys = { id = "" } end

  local fields, values = {}, {}
  local where = self:build_where_fields(where_keys)

  -- Build the VALUES to insert
  for k,_ in pairs(self._schema) do
    table.insert(fields, k)
    -- value is specified in entity and not in where_keys
    if entity[k] ~= nil and where_keys[k] == nil then
      table.insert(values, ":"..k)
    -- value is not specified in entity, thus is not to update, thus we select the existing one
    else
      table.insert(values, "(SELECT "..k.." FROM "..self._collection..where..")")
    end
  end

  return [[ INSERT OR REPLACE INTO ]]..self._collection..[[ ( ]]..table.concat(fields, ",")..[[ )
              VALUES( ]]..table.concat(values, ",")..[[ ); ]]
end

-- Build a DELETE statement from a table of keys to delete from
-- @param table where_keys Selector for the row(s) to delete
-- @return string The computed DELETE query to be binded
function BaseDao:build_delete_query(where_keys)
  if where_keys == nil then where_keys = { id = "" } end

  local where = self:build_where_fields(where_keys)

  return [[ DELETE FROM ]]..self._collection..where
end

-- Build a WHERE statement from keys of a table
-- If the passed table is nil or empty, we return a space,
-- so all our query utils don't have to do supplementary checks
-- to know if the WHERE statement is empty or not.
-- Ex:
--  { public_dns = "host.com" } returns: WHERE public_dns = ?
--
-- @param table t
-- @return string WHERE statement or a space
function BaseDao:build_where_fields(t)
  if t == nil or utils.table_size(t) == 0 then return " " end

  local fields = {}

  for k,_ in pairs(t) do
    table.insert(fields, k.."=:"..k)
  end

  return " WHERE "..table.concat(fields, " AND ")
end

------------------
-- SQLite UTILS --
------------------

function BaseDao:get_error(status)
  return {
    status = result,
    message = self._db:errmsg()
  }
end

-- Execute a statement supposed to return one or many rows
-- @param stmt A sqlite3 prepared statement
-- @return table The results in an array
-- @return table an error if error
function BaseDao:exec_select_stmt(stmt)
  -- Execute query
  local results = {}
  local step_result = stmt:step()

  -- Aggregate rows
  while step_result == sqlite3.ROW do
    table.insert(results, stmt:get_named_values())
    step_result = stmt:step()
  end

  -- Reset statement and get status code
  local status = stmt:reset()

  -- Error handling
  if step_result == sqlite3.DONE and status == sqlite3.OK then
    return results
  else
    return nil, self:get_error(status)
  end
end

-- Execute a statement and returnw the number of rows affected
-- @param stmt A sqlite3 prepared statement
-- @return number Number of rows affected by the query
-- @return table an error if error
function BaseDao:exec_stmt_count_rows(stmt)
  -- Execute query
  local step_result = stmt:step()
  -- Reset statement and get status code
  local status = stmt:reset()

  -- Error handling
  if step_result == sqlite3.DONE and status == sqlite3.OK then
    return self._db:changes()
  else
    return nil, self:get_error(status)
  end
end

-- Execute a statement and returns the last inserted rowid
-- The statement can optionally return a row (useful for COUNT) statement
-- but this might be another method in the future
-- @param stmt A sqlite3 prepared statement
-- @return rowid if the statement does not return any row
--         value of the fetched row if the statement returns a row
--         nil if error
-- @return table an error if error
function BaseDao:exec_stmt_rowid(stmt)
  -- Execute query
  local results
  local step_result = stmt:step()

  -- Aggregate rows
  if step_result == sqlite3.ROW then
    results = stmt:get_uvalues()
    step_result = stmt:step()
  end

  -- Reset statement and get status code
  local status = stmt:reset()

  -- Error handling
  if step_result == sqlite3.DONE and status == sqlite3.OK then
    if results then
      return results
    else
      return self._db:last_insert_rowid()
    end
  else
    return nil, self:get_error(status)
  end
end

return BaseDao
