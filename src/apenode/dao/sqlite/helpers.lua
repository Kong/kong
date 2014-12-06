local _M = {}

function _M.iterator_to_table(it, a)
  local arr = {}
  for v in it, a, 0 do
    table.insert(arr, v)
  end
  return arr
end

return _M