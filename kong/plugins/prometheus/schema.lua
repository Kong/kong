local Errors = require "kong.dao.errors"


return {
  fields = {},
  self_check = function(schema, plugin_t, dao, is_update) -- luacheck: ignore 212
    if not ngx.shared.prometheus_metrics then
      return false,
             Errors.schema "ngx shared dict 'prometheus_metrics' not found"
    end
    return true
  end,
}
