local utils = require "kong.tools.utils"
local constants = require "kong.constants"

local function load_value_schema(plugin_t)
  if plugin_t.name then
    local loaded, plugin_schema = utils.load_module_if_exists("kong.plugins."..plugin_t.name..".schema")
    if loaded then
      return plugin_schema
    else
      return nil, "Plugin \""..(plugin_t.name and plugin_t.name or "").."\" not found"
    end
  end
end

return {
  id = { type = constants.DATABASE_TYPES.ID },
  api_id = { type = constants.DATABASE_TYPES.ID, required = true, foreign = true, queryable = true },
  consumer_id = { type = constants.DATABASE_TYPES.ID, foreign = true, queryable = true, default = constants.DATABASE_NULL_ID },
  name = { type = "string", required = true, queryable = true, immutable = true },
  value = { type = "table", schema = load_value_schema },
  enabled = { type = "boolean", default = true },
  created_at = { type = constants.DATABASE_TYPES.TIMESTAMP }
}
