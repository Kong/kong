-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local _M = {}


function _M.init(config)
  if not config.keyring_enabled then
    return
  end

  local strategy = require("kong.keyring.strategies." .. config.keyring_strategy)
  require("kong.keyring").set_strategy(config.keyring_strategy)
  return strategy.init(config)
end


function _M.init_worker(config)
  if not config.keyring_enabled then
    return
  end

  local strategy = require("kong.keyring.strategies." .. config.keyring_strategy)
  return strategy.init_worker(config)
end


return _M
