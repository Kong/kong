local _M = {}
local mt = { __index = _M }


function _M:new()
  local self = {}
  return setmetatable(self, mt)
end


function _M:flush_data()
end


function _M:pull_data()
end


return _M
