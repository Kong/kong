local crud    = require "kong.api.crud_helpers"
local utils   = require "kong.tools.utils"
local reports = require "kong.core.reports"

local function post_process_label_from_id(self, dao_factory, helpers, data)
  self.params.label_name_or_id = data.label_id
  crud.find_label_by_name_or_id(self, dao_factory, helpers)
  return self.label
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

  ["/apis/:api_name_or_id/plugins/"] = {
    before = function(self, dao_factory, helpers)
      crud.find_api_by_name_or_id(self, dao_factory, helpers)
      self.params.api_id = self.api.id
    end,

    GET = function(self, dao_factory)
      crud.paginated_set(self, dao_factory.plugins)
    end,

    POST = function(self, dao_factory)
      crud.post(self.params, dao_factory.plugins, function(data)
        local r_data = utils.deep_copy(data)
        r_data.config = nil
        reports.send("api", r_data)
      end)
    end,

    PUT = function(self, dao_factory)
      crud.put(self.params, dao_factory.plugins)
    end
  },

  ["/apis/:api_name_or_id/plugins/:id"] = {
    before = function(self, dao_factory, helpers)
      crud.find_api_by_name_or_id(self, dao_factory, helpers)
      crud.find_plugin_by_filter(self, dao_factory, {
        api_id = self.api.id,
        id     = self.params.id,
      }, helpers)
    end,

    GET = function(self, dao_factory, helpers)
      return helpers.responses.send_HTTP_OK(self.plugin)
    end,

    PATCH = function(self, dao_factory)
      crud.patch(self.params, dao_factory.plugins, self.plugin)
    end,

    DELETE = function(self, dao_factory)
      crud.delete(self.plugin, dao_factory.plugins)
    end
  },

  ["/apis/:api_name_or_id/labels/"] = {
    before = function(self, dao_factory, helpers)
      crud.find_api_by_name_or_id(self, dao_factory, helpers)
      self.params.api_id = self.api.id
    end,

    GET = function(self, dao_factory, helpers)
      crud.paginated_set(self, dao_factory.label_mappings, function(data)
        return post_process_label_from_id(self, dao_factory, helpers, data)
      end)
    end,

    POST = function(self, dao_factory, helpers)
      -- TODO check if label_id is present or not
      crud.post(self.params, dao_factory.label_mappings, function(data)
        return post_process_label_from_id(self, dao_factory, helpers, data)
      end)
    end,
  },

  ["/apis/:api_name_or_id/labels/:label_name_or_id"] = {
    before = function(self, dao_factory, helpers)
      -- lookup api
      crud.find_api_by_name_or_id(self, dao_factory, helpers)

      -- lookup label
      crud.find_label_by_name_or_id(self, dao_factory, helpers)


      -- return 404 if no mapping between label and api
      local rows, err = dao_factory.label_mappings:find_all {
        label_id = self.label.id,
        api_id = self.api.id,
      }
      if err then
        return helpers.yield_error(err)
      end

      self.label_mapping = rows[1]
      if not self.label_mapping then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end

      -- self.api, self.label, self.label_mapping populated
    end,

    GET = function(self, dao_factory, helpers)
      return helpers.responses.send_HTTP_OK(self.label)
    end,

    DELETE = function(self, dao_factory)
      crud.delete(self.label_mapping, dao_factory.label_mappings)
    end
  },
}
