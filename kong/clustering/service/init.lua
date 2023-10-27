local _M = {}
local _MT = { __index = _M, }


local svcs = {
  "ping",
}


function _M.new()
  local self = {
    svcs = {},
  }

  for _, name in ipairs(svcs) do
    local mod = require("kong.clustering.service." .. name)
    self.svcs[name] = mod.new()
  end

  return setmetatable(self, _MT)
end


function _M:init()
  for _, svc in pairs(self.svcs) do
    svc.init()
  end
end


return _M
