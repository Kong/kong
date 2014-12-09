local _M = {}

function _M.select_paginated(stmt, page, size)
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

  stmt:reset()

  -- Error handling
  if step_result == sqlite3.ERROR then
    return nil, "SQLite error" -- call stmt:reset() here and/or db:errmsg()
  elseif step_result == sqlite3.DONE then
    return results
  end
end

function _M.select_by_key(stmt, value)

end

function _M.save()

end

function _M.update()

end

function _M.delete()

end

return _M
