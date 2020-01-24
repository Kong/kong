
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
