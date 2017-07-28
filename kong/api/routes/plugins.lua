local crud = require "kong.api.crud_helpers"
local cjson = require "cjson"
local utils = require "kong.tools.utils"
local reports = require "kong.core.reports"
local singletons = require "kong.singletons"

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
    GET = function(self, dao_factory)
      crud.paginated_set(self, dao_factory.plugins)
    end,

    PUT = function(self, dao_factory)
      crud.put(self.params, dao_factory.plugins)
    end,

    POST = function(self, dao_factory)
      crud.post(self.params, dao_factory.plugins, function(data)
        reports.send("api", utils.deep_copy(data))
      end)
    end
  },

  ["/plugins/schema/:name"] = {
    GET = function(self, dao_factory, helpers)
      local ok, plugin_schema = utils.load_module_if_exists("kong.plugins." .. self.params.name .. ".schema")
      if not ok then
        return helpers.responses.send_HTTP_NOT_FOUND("No plugin named '" .. self.params.name .. "'")
      end

      remove_functions(plugin_schema)

      return helpers.responses.send_HTTP_OK(plugin_schema)
    end
  },

  ["/plugins/:id"] = {
    before = function(self, dao_factory, helpers)
      local rows, err = dao_factory.plugins:find_all {id = self.params.id}
      if err then
        return helpers.yield_error(err)
      elseif #rows == 0 then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end

      self.plugin_conf = rows[1]
    end,

    GET = function(self, dao_factory, helpers)
      return helpers.responses.send_HTTP_OK(self.plugin_conf)
    end,

    PATCH = function(self, dao_factory)
      crud.patch(self.params, dao_factory.plugins, self.plugin_conf)
    end,

    DELETE = function(self, dao_factory)
      crud.delete(self.plugin_conf, dao_factory.plugins)
    end
  },

  ["/plugins/enabled"] = {
    GET = function(self, dao_factory, helpers)
      local enabled_plugins = setmetatable({}, cjson.empty_array_mt)
      for k in pairs(singletons.configuration.plugins) do
        enabled_plugins[#enabled_plugins+1] = k
      end
      return helpers.responses.send_HTTP_OK {
        enabled_plugins = enabled_plugins
      }
    end
  }
}
