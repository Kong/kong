local DaoError = require "kong.dao.error"
local utils = require "kong.tools.utils"
local constants = require "kong.constants"

return {
  no_consumer = true,
  fields = {
    whitelist = { type = "array" },
    blacklist = { type = "array" }
  },
  self_check = function(schema, plugin_t, dao, is_update)
    if utils.table_size(plugin_t.whitelist) > 0 and utils.table_size(plugin_t.blacklist) > 0 then
      return false, DaoError("You cannot set both a whitelist and a blacklist", constants.DATABASE_ERROR_TYPES.SCHEMA)
    elseif utils.table_size(plugin_t.whitelist) == 0 and utils.table_size(plugin_t.blacklist) == 0 then
      return false, DaoError("You must set at least a whitelist or blacklist", constants.DATABASE_ERROR_TYPES.SCHEMA)
    end
    return true
  end
}