local Factory = require "kong.dao.factory"

local _M = {}

function _M.load(config, events_handler)
  return Factory(config.database, config.dao_config)
end

return _M
