local Errors = require "kong.dao.errors"
local utils = require "kong.tools.utils"

return {
  no_consumer = true,
  fields = {
    whitelist = { type = "array" },
    blacklist = { type = "array" }
  },
  self_check = function(schema, plugin_t, dao, is_update)
    if utils.table_size(plugin_t.whitelist) > 0 and utils.table_size(plugin_t.blacklist) > 0 then
      return false, Errors.schema "You cannot set both a whitelist and a blacklist"
    elseif utils.table_size(plugin_t.whitelist) == 0 and utils.table_size(plugin_t.blacklist) == 0 then
      return false, Errors.schema "You must set at least a whitelist or blacklist"
    end
    return true
  end
}
