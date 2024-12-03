local EMPTY = require("kong.tools.table").EMPTY
local inplace_merge = require("kong.db.resumable_chunker.utils").inplace_merge

local _M = {}
local _MT = { __index = _M }

local BEGIN = { 1, nil }

function _M.from_chain(list, options)
  options = options or EMPTY
  list.options = options
  return setmetatable(list, _MT)
end

function _M:next(size, offset)
  size = size or self.options.size
  offset = offset or BEGIN
  local ind, inner_ind = offset[1], offset[2]

  if not self[ind] then
    return EMPTY
  end

  local rows, len = nil, 0
  repeat
    local next_row, err
    next_row, err, inner_ind = self[ind]:next(size - len, inner_ind)
    if not next_row then
      return nil, err, { ind, inner_ind }
    end
    rows, len = inplace_merge(rows, next_row)

    if not inner_ind then -- end of the current chain. continue with the next one
      ind = ind + 1
    end
  until len >= size or not self[ind]
  
  return rows or EMPTY, nil, self[ind] and { ind, inner_ind } or nil
end

return _M
