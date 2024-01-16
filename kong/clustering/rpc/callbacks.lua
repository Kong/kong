local _M = {}
local _MT = { __index = _M, }


local utils = require("kong.clustering.rpc.utils")


local pairs = pairs
local parse_method_name = utils.parse_method_name
local unpack = table.unpack


function _M.new()
  local self = {
    callbacks = {},
  }

  return setmetatable(self, _MT)
end


function _M:register(method, func)
  if self.callbacks[method] then
    error("duplicate registration of " .. method)
  end

  if not func then
    error("missing callback function for " .. method)
  end

  self.callbacks[method] = func
end


function _M:get_capabilities()
  local capabilities = {}

  for m in pairs(self.callbacks) do
    local cap, func_or_err = parse_method_name(m)
    if not cap then
      return nil, "unable to get capabilities: " .. func_or_err
    end

    capabilities[cap] = true
  end

  return capabilities
end


return _M
