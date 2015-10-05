local _M = {}

function _M.load(config)
  local DaoFactory = require("kong.dao."..config.database..".factory")
  return DaoFactory(config.dao_config, config.plugins_available)
end

return _M
