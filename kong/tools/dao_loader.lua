local _M = {}

function _M.load(config, events_handler, spawn_cluster)
  local DaoFactory = require("kong.dao."..config.database..".dao_factory")
  return DaoFactory(config.dao_config, config.plugins, events_handler, spawn_cluster)
end

return _M
