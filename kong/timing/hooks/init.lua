-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local _M = {}

-- order matters
local HOOKS = {
  "socket",
  "dns",
  "http",
  "redis",
  -- XXX EE [[
  "rediscluster"
  -- XXX EE ]]
}


function _M.register_hooks(timing_module)
  for _, hook_name in ipairs(HOOKS) do
    local hook_module = require("kong.timing.hooks." .. hook_name)
    hook_module.register_hooks(timing_module)
  end
end


return _M
