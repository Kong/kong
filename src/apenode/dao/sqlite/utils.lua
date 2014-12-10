local _M = {}

-- Execute a statement supposed to return a page
-- @param stmt A sqlite3 prepared statement
-- @param page The page to query
-- @param size The size of the page
-- @return A list of tables representing the fetched entities, nil if error
-- @return A sqlite3 status code if error
function _M.exec_paginated_stmt(stmt, page, size)
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
    return nil, status
  end
end

-- Execute a statement supposed to return one row
-- @param stmt A sqlite3 prepared statement
-- @return A table representing the fetched entity, nil if error
-- @return A sqlite3 status code if error
function _M.exec_select_stmt(stmt)
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
    return nil, status
  end
end

-- Execute a simple statement
-- The statement can optionally return a row (useful for COUNT) statement
-- but this might be another method in the future
-- @param stmt A sqlite3 prepared statement
-- @return true if the statement does not return any row
--         value of the fetched row if the statement returns a row
--         nil if error
-- @return A sqlite3 status code if error
function _M.exec_stmt(stmt)
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
    if results then return results else return true end;
  else
    return nil, status
  end
end

return _M
