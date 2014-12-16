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

function BaseDao:_init(database, collection)
  self._db = database

  -- Cache the prepared statements if already prepared
  self._stmt_cache = {}
end

--
-- Ex:
-- { name = "api name", key = "value" }
-- Returns: "name, key", ":name, :key"
-- @param table Entity to build fields for
-- @return string Built string for fields
-- @return string Built string for bindings
function BaseDao:build_insert_fields(entity)
  local names, bindings = {}, {}
  for k,_ in pairs(entity) do
    table.insert(names, k)
    table.insert(bindings, ":"..k)
  end

  return table.concat(names, ","), table.concat(bindings, ",")
end

--
-- Ex:
-- { name = "api name", key = "value" }
-- Returns: "name = :name, key = :key"
-- @param table Entity to build fields for
-- @return string Built string for update statement
function BaseDao:build_update_fields(entity)
  local fields = {}
  for k,_ in pairs(entity) do
    table.insert(fields, k.."=:"..k)
  end

  return table.concat(fields, ",")
end

function BaseDao:build_where_fields(t)
  local fields = {}
  for k,_ in pairs(t) do
    table.insert(fields, k.."=:"..k)
  end

  return table.concat(fields, " AND ")
end

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

function BaseDao:save(entity)
  local field_names, field_bindings = BaseDao:build_insert_fields(entity)
  local stmt = BaseDao:get_statement("INSERT INTO "..self._collection.."("..field_names..") VALUES("..field_bindings..")")

  stmt:bind_names(entity)

  local inserted_id, err = self:exec_stmt(stmt)
  if err then
    return nil, err
  end

  entity.id = inserted_id
  return entity
end

function BaseDao:update(keys, entity)
  local update_fields = self:build_update_fields(entity)
  local where_fields = self:build_where_fields(keys)
  local stmt = BaseDao:get_statement("UPDATE "..self._collection.." SET "..update_fields.." WHERE "..where_fields)

  stmt:bind_names(entity)
  stmt:bind_names(keys)

  local rowid, err = self:exec_stmt(stmt)
  if err then
    return nil, err
  end

  return entity
end

function BaseDao:delete(id)
  self.delete_stmt:bind_values(id)
  return self:exec_stmt(self.delete_stmt)
end

function BaseDao:get_by_id(id)
  self.select_by_id_stmt:bind_values(id)
  return self:exec_select_stmt(self.select_by_id_stmt)
end

function BaseDao:get_all(page, size)
  -- TODO all in one query
  local results, err = self:exec_paginated_stmt(self.select_all_stmt, page, size)
  if err then
    return nil, nil, err
  end

  local count, err = self:exec_stmt(self.select_count_stmt)
  if err then
    return nil, nil, err
  end

  return results, count
end

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
  if not page then page = 1 end
  if not size then size = 30 end
  size = math.min(size, 100)

  local results = {}
  local start_offset = ((page - 1) * size)

  -- values binding
  stmt:bind_names { page = start_offset, size = size }

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
