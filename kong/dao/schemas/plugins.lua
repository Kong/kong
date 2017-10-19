local utils = require "kong.tools.utils"
local Errors = require "kong.dao.errors"

local function load_config_schema(plugin_t)
  if plugin_t.name then
    local loaded, plugin_schema = utils.load_module_if_exists("kong.plugins." .. plugin_t.name .. ".schema")
    if loaded then
      return plugin_schema
    else
      return nil, 'Plugin "' .. tostring(plugin_t.name) .. '" not found'
    end
  end
end

return {
  table = "plugins",
  primary_key = {"id", "name"},
  cache_key = { "name", "api_id", "consumer_id" },
  fields = {
    id = {
      type = "id",
      dao_insert_value = true,
      required = true,
      unique = true,
    },
    created_at = {
      type = "timestamp",
      immutable = true,
      dao_insert_value = true,
      required = true
    },
    api_id = {
      type = "id",
      foreign = "apis:id"
    },
    consumer_id = {
      type = "id",
      foreign = "consumers:id"
    },
    name = {
      type = "string",
      required = true,
      immutable = true
    },
    config = {
      type = "table",
      schema = load_config_schema,
      default = {}
    },
    enabled = {
      type = "boolean",
      default = true
    }
  },
  self_check = function(self, plugin_t, dao, is_update)
    -- Load the config schema
    local config_schema, err = self.fields.config.schema(plugin_t)
    if err then
      return false, Errors.schema(err)
    end

    -- Check if the schema has a `no_consumer` field
    if config_schema.no_consumer and plugin_t.consumer_id ~= nil then
      return false, Errors.schema "No consumer can be configured for that plugin"
    end

    if config_schema.self_check and type(config_schema.self_check) == "function" then
      local ok, err = config_schema.self_check(config_schema, plugin_t.config and plugin_t.config or {}, dao, is_update)
      if not ok then
        return false, err
      end
    end

    if not is_update then
      local rows, err = dao:find_all {
        name = plugin_t.name,
        api_id = plugin_t.api_id,
        consumer_id = plugin_t.consumer_id
      }
      if err then
        return false, err
      elseif #rows > 0 then
        for _, row in ipairs(rows) do
          if row.name == plugin_t.name and row.api_id == plugin_t.api_id and row.consumer_id == plugin_t.consumer_id then
            return false, Errors.unique { name = plugin_t.name }
          end
        end
      end
    end
  end
}
