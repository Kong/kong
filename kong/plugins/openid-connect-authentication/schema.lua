local utils  = require "kong.tools.utils"
local errors = require "kong.dao.errors"

return {
  no_consumer = true,
  fields      = {},
  self_check  = function(schema, plugin_t, dao, is_update)
  end
}
