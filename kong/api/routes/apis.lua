local kong = kong
local crud = require "kong.api.crud_helpers"
local utils = require "kong.tools.utils"
local reports = require "kong.reports"
local endpoints = require "kong.api.endpoints"
local arguments = require "kong.api.arguments"


local get_api_plugin = endpoints.get_collection_endpoint(kong.db.plugins.schema,
                                                         kong.db.apis.schema,
                                                         "api")
local post_api_plugin = endpoints.post_collection_endpoint(kong.db.plugins.schema,
                                                           kong.db.apis.schema,
                                                           "api")


local function post_process(data)
  local r_data = utils.deep_copy(data)
  r_data.config = nil
  r_data.e = "a"
  reports.send("api", r_data)
  return data
end


return {
  ["/apis/"] = {
    GET = function(self, dao_factory)
      crud.paginated_set(self, dao_factory.apis)
    end,

    PUT = function(self, dao_factory)
      crud.put(self.params, dao_factory.apis)
    end,

    POST = function(self, dao_factory)
      crud.post(self.params, dao_factory.apis)
    end
  },

  ["/apis/:api_name_or_id"] = {
    before = function(self, dao_factory, helpers)
      crud.find_api_by_name_or_id(self, dao_factory, helpers)
    end,

    GET = function(self, dao_factory, helpers)
      return helpers.responses.send_HTTP_OK(self.api)
    end,

    PATCH = function(self, dao_factory)
      crud.patch(self.params, dao_factory.apis, self.api)
    end,

    DELETE = function(self, dao_factory)
      crud.delete(self.api, dao_factory.apis)
    end
  },

  ["/apis/:apis/plugins/"] = {
    GET = function(self, dao, helpers)
      return get_api_plugin(self, dao.db.new_db, helpers)
    end,

    POST = function(self, dao, helpers)
      self.args = arguments.load({
        schema  = kong.db.plugins.schema,
        request = self.req,
      })
      return post_api_plugin(self, dao.db.new_db, helpers, post_process)
    end
  },

}
