-- Copyright (C) Mashape, Inc.

local BaseDao = {}
BaseDao.__index = BaseDao

setmetatable(BaseDao, {
  __call = function (cls, ...)
    local self = setmetatable({}, cls)
    self:_init(...)
    return self
  end
})

function BaseDao._init(instance, database, collection, schema)
  instance._db = database
  instance._collection = collection
  instance._schema = schema

  -- Cache the prepared statements if already prepared
  instance._stmt_cache = {}
end

-- Insert or update an entity
-- @param table entity Entity to insert or replace
-- @param table where_keys Selector for the row to insert or update
-- @return table Inserted/updated entity with its rowid property
-- @return table Error if error
function BaseDao:insert_or_update(entity, where_keys)
  if not entity then entity = {} end
  local query = self:build_insert_or_update_query(entity, where_keys)
  local stmt = self:get_statement(query)
  stmt:bind_names(entity)

  local rowid, err = self:exec_stmt(stmt)
  if err then
    return nil, err
  end

  entity.id = rowid

  return entity
end

-- Find one row according to a condition determined by the keys
-- @param table keys Keys used to build a WHERE condition
-- @param table where_keys Selector for the row to insert or update
-- @return table Retrieved row or nil
-- @return table Error if error
function BaseDao:find_one(where_keys)
  local query = self:build_select_query(where_keys)
  local stmt = self:get_statement(query)

  where_keys.page = 1
  stmt:bind_names(where_keys)

  return self:exec_select_stmt(stmt)
end

function BaseDao:find(where_keys, page, size)
  if type(where_keys) ~= "table" then
    size = page
    page = where_keys
    where_keys = nil
  end

  if not page then page = 1 end
  if not size then size = 30 end
  size = math.min(size, 100)

  local start_offset = ((page - 1) * size)

  local query = self:build_select_query(where_keys, true)
  local count_query = self:build_count_query(where_keys)
  local stmt = self:get_statement(query)
  local count_stmt = self:get_statement(count_query)

  local k = {}
  if where_keys then
    k = where_keys
  end

  k.page = start_offset
  k.size = size

  stmt:bind_names(k)
  count_stmt:bind_names(k)

  local results, err = self:exec_paginated_stmt(stmt, page, size)
  if err then
    return nil, nil, err
  end

  local count_result, err = self:exec_stmt(count_stmt)
  if err then
    return nil, nil, err
  end

  return results, count_result
end

function BaseDao:delete_by_keys(keys)

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
      error("SQLite Error. Failed to prepare statement: "..self._db:errmsg())
    else
      self._stmt_cache[query] = statement
      return statement
    end
  end
end

-- Build a SELECT query on the current collection and model schema
-- with a WHERE condition
-- @param table where_keys Selector for the row to select
-- @param
-- @return string The computed SELECT statement
function BaseDao:build_select_query(where_keys, paginated)
  local where = self:build_where_fields(where_keys)
  local query = [[ SELECT * FROM ]]..self._collection

  if where ~= nil then
    query = query..where
  end

  query = query..[[ LIMIT :page ]]

  if paginated then
    query = query..[[, :size]]
  end

  return query
end

function BaseDao:build_count_query(where_keys)
  local where = self:build_where_fields(where_keys)
  local query = [[ SELECT COUNT(*) FROM ]]..self._collection

  if where then
    query = query..where
  end

  return query
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
-- @return string The computed INSERT OR REPLACE statement
function BaseDao:build_insert_or_update_query(entity, where_keys)
  if where_keys == nil then where_keys = { id = "" } end

  local fields, values = {}, {}
  local where = self:build_where_fields(where_keys)

  -- Build the VALUES to insert
  for k,_ in pairs(self._schema) do
    table.insert(fields, k)
    -- value is specified in entity
    if entity[k] ~= nil then
      table.insert(values, ":"..k)
    -- value is not specified in entity, thus is not to update, thus we select the existing one
    else
      table.insert(values, "(SELECT "..k.." FROM "..self._collection..where..")")
    end
  end

  return [[ INSERT OR REPLACE INTO ]]..self._collection..[[ ( ]]..table.concat(fields, ",")..[[ )
              VALUES( ]]..table.concat(values, ",")..[[ ); ]]
end

-- Build a WHERE statement from an array of
-- Ex:
--
-- @param table t
-- @return string WHERE statement or nil
function BaseDao:build_where_fields(t)
  if t == nil then return nil end

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

-- Execute a statement supposed to return a page
-- @param stmt A sqlite3 prepared statement
-- @param page The page to query
-- @param size The size of the page
-- @return A list of tables representing the fetched entities, nil if error
-- @return A sqlite3 status code if error
function BaseDao:exec_paginated_stmt(stmt, page, size)
  local results = {}
  -- values binding
  --stmt:bind_names { page = start_offset, size = size }

  -- Execute query
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

-- Execute a statement supposed to return one row
-- @param stmt A sqlite3 prepared statement
-- @return A table representing the fetched entity, nil if error
-- @return A sqlite3 status code if error
function BaseDao:exec_select_stmt(stmt)
  -- Execute query
  local results
  local step_result = stmt:step()

  -- Aggregate rows
  if step_result == sqlite3.ROW then
    results = stmt:get_named_values()
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

-- Execute a simple statement
-- The statement can optionally return a row (useful for COUNT) statement
-- but this might be another method in the future
-- @param stmt A sqlite3 prepared statement
-- @return rowid if the statement does not return any row
--         value of the fetched row if the statement returns a row
--         nil if error
-- @return A sqlite3 status code if error
function BaseDao:exec_stmt(stmt)
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
