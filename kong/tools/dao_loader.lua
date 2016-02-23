local Factory = require "kong.dao.factory"

local _M = {}

function _M.load(config, events_handler)
  return Factory(config.database, config.dao_config, config.plugins)
end

return _M
