-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local require = require
local setmetatable = setmetatable


local _M = {}

_M.STRATEGY_TYPES = {
  "memory",
  "redis",
}

-- strategies that should delay writing cache storage to
-- a dummy req, rather than doing so at the last body filter execution
_M.DELAY_STRATEGY_STORE = {
  redis = true,
}

-- strategies that store cache data only on the node, instead of
-- cluster-wide. this is typically used to handle purge notifications
_M.LOCAL_DATA_STRATEGIES = {
  memory = true,
  [1]    = "memory",
}

local function require_strategy(name)
  return require("kong.plugins.proxy-cache-advanced.strategies." .. name)
end

return setmetatable(_M, {
  __call = function(_, opts)
    return require_strategy(opts.strategy_name).new(opts.strategy_opts)
  end
})
