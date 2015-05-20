local validations = require "kong.dao.schemas"
local crud = require "kong.api.crud_helpers"

local function find_by_name_or_id(self, dao_factory, helpers)
  local fetch_keys = {
    [validations.is_valid_uuid(self.params.name_or_id) and "id" or "name"] = self.params.name_or_id
  }
  self.params.name_or_id = nil

  -- TODO: make the base_dao more flexible so we can query find_one with key/values
  -- https://github.com/Mashape/kong/issues/103
  local data, err = dao_factory.apis:find_by_keys(fetch_keys)
  if err then
    return helpers.yield_error(err)
  end

  self.api = data[1]
  if not self.api then
    return helpers.responses.send_HTTP_NOT_FOUND()
  end
end

return {
  ["/apis/"] = {
    GET = function(self, dao_factory)
      crud.paginated_set(self, dao_factory.apis)
    end,

    PUT = function(self, dao_factory)
      crud.put(self, dao_factory.apis)
    end,

    POST = function(self, dao_factory)
      crud.post(self, dao_factory.apis)
    end
  },

  ["/apis/:name_or_id"] = {
    before = find_by_name_or_id,

    GET = function(self, dao_factory, helpers)
      return helpers.responses.send_HTTP_OK(self.api)
    end,

    PATCH = function(self, dao_factory)
      self.params.id = self.api.id
      crud.patch(self.params, dao_factory.apis)
    end,

    DELETE = function(self, dao_factory)
      crud.delete(self.api.id, dao_factory.apis)
    end
  },

  ["/apis/:name_or_id/plugins/"] = {
    before = function(self, dao_factory, helpers)
      find_by_name_or_id(self, dao_factory, helpers)
      self.params.api_id = self.api.id
    end,

    GET = function(self, dao_factory)
      crud.paginated_set(self, dao_factory.plugins_configurations)
    end,

    POST = function(self, dao_factory, helpers)
      crud.post(self, dao_factory.plugins_configurations)
    end,

    PUT = function(self, dao_factory, helpers)
      crud.put(self, dao_factory.plugins_configurations)
    end
  }
}
