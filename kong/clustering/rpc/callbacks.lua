-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local _M = {}
local _MT = { __index = _M, }


local cjson = require("cjson.safe")
local utils = require("kong.clustering.rpc.utils")


local parse_method_name = utils.parse_method_name


function _M.new()
  local self = {
    callbacks = {},
    capabilities = {}, -- updated as register() is called
    capabilities_list = {}, -- updated as register() is called
  }

  -- it should always be an array when json encoding
  setmetatable(self.capabilities_list, cjson.array_mt)

  return setmetatable(self, _MT)
end


function _M:register(method, func)
  if self.callbacks[method] then
    error("duplicate registration of " .. method)
  end

  local cap, func_or_err = parse_method_name(method)
  if not cap then
    return nil, "unable to get capabilities: " .. func_or_err
  end

  if not self.capabilities[cap] then
    self.capabilities[cap] = true
    table.insert(self.capabilities_list, cap)
  end
  self.callbacks[method] = func
end


-- returns a list of capabilities of this node, like:
-- ["kong.meta.v1", "kong.debug.v1", ...]
function _M:get_capabilities_list()
  return self.capabilities_list
end


return _M
