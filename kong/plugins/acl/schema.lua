local Errors = require "kong.dao.errors"
local utils = require "kong.tools.utils"

return {
  no_consumer = true,
  fields = {
    whitelist = { type = "array" },
    blacklist = { type = "array" }
  },
  self_check = function(schema, plugin_t, dao, is_update)
    if next(plugin_t.whitelist) and next(plugin_t.blacklist) then
      return false, Errors.schema "You cannot set both a whitelist and a blacklist"
    elseif not (next(plugin_t.whitelist) or next(plugin_t.blacklist)) then
      return false, Errors.schema "You must set at least a whitelist or blacklist"
    end
    return true
  end
}
