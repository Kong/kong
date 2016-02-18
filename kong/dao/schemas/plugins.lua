local utils = require "kong.tools.utils"
local Errors = require "kong.dao.errors"
local DaoError = require "kong.dao.error"
local constants = require "kong.constants"

local function load_config_schema(plugin_t)
  if plugin_t.name then
    local loaded, plugin_schema = utils.load_module_if_exists("kong.plugins."..plugin_t.name..".schema")
    if loaded then
      return plugin_schema
    else
      return nil, 'Plugin "'..tostring(plugin_t.name)..'" not found'
    end
  end
end

return {
  name = "Plugin configuration",
  table = "plugins",
  primary_key = {"id", "name"},
  clustering_key = {"name"},
  fields = {
    id = {
      type = "id",
      dao_insert_value = true
    },
    created_at = {
      type = "timestamp",
      immutable = true,
      dao_insert_value = true
    },
    api_id = {
      type = "id",
      required = true,
      foreign = "apis:id",
      queryable = true
    },
    consumer_id = {
      type = "id",
      foreign = "consumers:id",
      queryable = true,
      --default = constants.DATABASE_NULL_ID
    },
    name = {
      type = "string",
      required = true,
      immutable = true,
      queryable = true
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
  marshall_event = function(self, plugin_t)
    local result = utils.deep_copy(plugin_t)
    if plugin_t and plugin_t.config then
      local config_schema, err = self.fields.config.schema(plugin_t)
      if err then
        return false, DaoError(err, constants.DATABASE_ERROR_TYPES.SCHEMA)
      end

      if config_schema.marshall_event and type(config_schema.marshall_event) == "function" then
        result.config = config_schema.marshall_event(plugin_t.config)
      else
        result.config = {}
      end
    end
    return result
  end,
  self_check = function(self, plugin_t, dao, is_update)
    -- Load the config schema
    local config_schema, err = self.fields.config.schema(plugin_t)
    if err then
      return false, DaoError(err, constants.DATABASE_ERROR_TYPES.SCHEMA)
    end

    -- Check if the schema has a `no_consumer` field
    if config_schema.no_consumer and plugin_t.consumer_id ~= nil and plugin_t.consumer_id ~= constants.DATABASE_NULL_ID then
      return false, DaoError("No consumer can be configured for that plugin", constants.DATABASE_ERROR_TYPES.SCHEMA)
    end

    if config_schema.self_check and type(config_schema.self_check) == "function" then
      local ok, err = config_schema.self_check(config_schema, plugin_t.config and plugin_t.config or {}, dao, is_update)
      if not ok then
        return false, err
      end
    end

    if not is_update then
      local rows, err = dao:filter {
        name = plugin_t.name,
        api_id = plugin_t.api_id,
        consumer_id = plugin_t.consumer_id
      }
      if err then
        return false, err
      elseif #rows > 0 then
        for _, row in ipairs(rows) do
          if row.name == plugin_t.name and row.api_id == plugin_t.api_id and row.consumer_id == plugin_t.consumer_id then
            return false, Errors.unique "Plugin configuration already exists"
          end
        end
      end
    end
  end
}
