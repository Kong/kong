local validations = require("kong.dao.schemas")

return {
  ["/apis/"] = {
    GET = function(self, dao_factory, helpers)
      helpers.return_paginated_set(self, dao_factory.apis)
    end,

    PUT = function(self, dao_factory, helpers)
      local new_api, err
      if self.params.id then
        new_api, err = dao_factory.apis:update(self.params)
        if not err then
          return helpers.responses.send_HTTP_OK(new_api)
        end
      else
        new_api, err = dao_factory.apis:insert(self.params)
        if not err then
          return helpers.responses.send_HTTP_CREATED(new_api)
        end
      end

      if err then
        return helpers.yield_error(err)
      end
    end,

    POST = function(self, dao_factory, helpers)
      local data, err = dao_factory.apis:insert(self.params)
      if err then
        return helpers.yield_error(err)
      else
        return helpers.responses.send_HTTP_CREATED(data)
      end
    end
  },

  ["/apis/:name_or_id"] = {
    before = function(self, dao_factory, helpers)
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
    end,

    GET = function(self, dao_factory, helpers)
      return helpers.responses.send_HTTP_OK(self.api)
    end,

    PATCH = function(self, dao_factory, helpers)
      self.params.id = self.api.id

      local new_api, err = dao_factory.apis:update(self.params)
      if err then
        return helpers.yield_error(err)
      else
        return helpers.responses.send_HTTP_OK(new_api)
      end
    end
  }
}

