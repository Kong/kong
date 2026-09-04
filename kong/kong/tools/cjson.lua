local cjson = require "cjson.safe".new()
local CJSON_MAX_PRECISION = require "kong.constants".CJSON_MAX_PRECISION
local new_tab = require("table.new")

local setmetatable = setmetatable
local array_mt = cjson.array_mt

cjson.decode_array_with_array_mt(true)
cjson.encode_sparse_array(nil, nil, 2^15)
cjson.encode_number_precision(CJSON_MAX_PRECISION)


local _M = {}


_M.encode = cjson.encode
_M.decode_with_array_mt = cjson.decode


_M.array_mt = array_mt

--- Creates a new table with the cjson array metatable.
---
--- This ensures that the table will be encoded as a JSON array, even if it
--- is empty.
---
---@param size? integer
---@return table
function _M.new_array(size)
  local t = size and new_tab(size, 0) or {}
  setmetatable(t, array_mt)
  return t
end

return _M
