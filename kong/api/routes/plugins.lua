local utils = require "kong.tools.utils"

-- Remove functions from a schema definition so that
-- cjson can encode the schema.
local function remove_functions(schema)
  for k, v in pairs(schema) do
    if type(v) == "function" then
      schema[k] = "function"
    end
    if type(v) == "table" then
      remove_functions(schema[k])
    end
  end
end

return {
  ["/plugins"] = {
    GET = function(self, dao_factory, helpers)
      return helpers.responses.send_HTTP_OK {
        enabled_plugins = configuration.plugins_available
      }
    end
  },
  ["/plugins/:name/schema"] = {
    GET = function(self, dao_factory, helpers)
      local ok, plugin_schema = utils.load_module_if_exists("kong.plugins."..self.params.name..".schema")
      if not ok then
        return helpers.responses.send_HTTP_NOT_FOUND("No plugin named '"..self.params.name.."'")
      end

      remove_functions(plugin_schema)

      return helpers.responses.send_HTTP_OK(plugin_schema)
    end
  }
}
