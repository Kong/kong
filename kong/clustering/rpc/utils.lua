local _M = {}
local pl_stringx = require("pl.stringx")


local string_sub = string.sub


local rfind = pl_stringx.rfind


function _M.parse_method_name(method)
  local pos = rfind(method, ".")
  if not pos then
    return nil, "not a valid method name"
  end

  return method:sub(1, pos - 1), method:sub(pos + 1)
end


function _M.is_timeout(err)
  return err and string_sub(err, -7) == "timeout"
end


return _M
