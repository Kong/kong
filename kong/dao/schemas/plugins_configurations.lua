local utils = require "kong.tools.utils"
local DaoError = require "kong.dao.error"
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
  name = "Plugin configuration",
  fields = {
    id = { type = "id", dao_insert_value = true },
    created_at = { type = "timestamp", dao_insert_value = true },
    api_id = { type = "id", required = true, foreign = "apis:id" },
    consumer_id = { type = "id", foreign = "consumers:id", default = constants.DATABASE_NULL_ID },
    name = { type = "string", required = true, immutable = true },
    value = { type = "table", schema = load_value_schema },
    enabled = { type = "boolean", default = true }
  },
  on_insert = function(plugin_t, dao)
    local res, err = dao.plugins_configurations:find_by_keys({
      name = plugin_t.name,
      api_id = plugin_t.api_id,
      consumer_id = plugin_t.consumer_id
    })

    if err then
      return nil, DaoError(err, constants.DATABASE_ERROR_TYPES.DATABASE)
    end

    if res and #res > 0 then
      return false, DaoError("Plugin configuration already exists", constants.DATABASE_ERROR_TYPES.UNIQUE)
    else
      return true
    end
  end
}
