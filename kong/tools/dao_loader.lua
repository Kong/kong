local Factory = require "kong.dao.factory"

local _M = {}

function _M.load(kong_config, events_handler)
  return Factory(kong_config, kong_config.plugins, events_handler)
end

return _M
