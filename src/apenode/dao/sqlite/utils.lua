local _M = {}

function _M.exec_paginated_stmt(stmt, page, size)
  if not page then page = 1 end
  if not size then size = 30 end
  -- Max size value
  size = math.min(size, 100)

  -- page offset
  local start_offset = ((page - 1) * size)
  local results = {}

  -- values binding
  stmt:bind_names { page = start_offset, size = size }

  -- Start query
  local step_result = stmt:step()

  while step_result == sqlite3.ROW do
    table.insert(results, stmt:get_named_values())
    step_result = stmt:step()
  end

  -- Reset statement and get status code
  local reset = stmt:reset()

  -- Error handling
  if step_result == sqlite3.DONE and reset == sqlite3.OK then
    return results
  else
    return nil, reset
  end
end

function _M.exec_select_stmt(stmt)
  -- Execute query
  local step_result, results = stmt:step()

  if step_result == sqlite3.ROW then
    results = stmt:get_named_values()
    step_result = stmt:step()
  end

  -- Reset statement and get status code
  local reset = stmt:reset()

  -- Error handling
  if step_result == sqlite3.DONE and reset == sqlite3.OK then
    return results
  else
    return nil, reset
  end
end

function _M.exec_stmt(stmt)
  -- Execute query
  local step_result = stmt:step()

  -- Reset statement and get status code
  local reset = stmt:reset()

  -- Error handling
  if step_result == sqlite3.DONE and reset == sqlite3.OK then
    return true
  else
    return nil, reset
  end
end

return _M
