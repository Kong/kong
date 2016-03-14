local _M = {}

function _M.load(config, spawn_cluster, events_handler)
  local DaoFactory = require("kong.dao."..config.database..".factory")
  return DaoFactory(config.dao_config, config.plugins, spawn_cluster, events_handler)
end

return _M