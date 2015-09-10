local crud = require "kong.api.crud_helpers"
local basic_auth_utils = require "kong.plugins.basic-auth.utils"

local function get_config(dao_factory)
  -- in case of no conf.
  local default_config = {
    hide_credentials = false,
    encryption_method = "plain",
  }

  local data, err = dao_factory.plugins:find_by_keys({ name = "basic-auth" })
  if err then
    return default_config, err
  end

  if not data[1] or not data[1].config then
    return default_config, "basic-auth configuration not found"
  end

  return data[1].config or default_config
end

local function prepare_password(self, dao_factory, helpers)
  local config, err = get_config(dao_factory)
  if err then
    ngx.log(ngx.ERR, "Error fetching basic-auth configuration: ", err)
  end

  local method = config.encryption_method or "plain"
  local transform_function = basic_auth_utils.encryption_methods[method] or basic_auth_utils.encryption_methods.plain
  return transform_function(self.params)
end

local global_route = {
  before = function(self, dao_factory, helpers)
    crud.find_consumer_by_username_or_id(self, dao_factory, helpers)
    self.params.consumer_id = self.consumer.id
    self.params.password = prepare_password(self, dao_factory, helpers)
  end,

  GET = function(self, dao_factory, helpers)
    crud.paginated_set(self, dao_factory.basicauth_credentials)
  end,

  PUT = function(self, dao_factory)
    crud.put(self.params, dao_factory.basicauth_credentials)
  end,

  POST = function(self, dao_factory)
    crud.post(self.params, dao_factory.basicauth_credentials)
  end
}

local single_route = {
  before = function(self, dao_factory, helpers)
    crud.find_consumer_by_username_or_id(self, dao_factory, helpers)
    self.params.consumer_id = self.consumer.id
    self.params.password = prepare_password(self, dao_factory, helpers)

    local data, err = dao_factory.basicauth_credentials:find_by_keys({ id = self.params.id })
    if err then
      return helpers.yield_error(err)
    end

    self.credential = data[1]
    if not self.credential then
      return helpers.responses.send_HTTP_NOT_FOUND()
    end
  end,

  GET = function(self, dao_factory, helpers)
    return helpers.responses.send_HTTP_OK(self.credential)
  end,

  PATCH = function(self, dao_factory)
    crud.patch(self.params, self.credential, dao_factory.basicauth_credentials)
  end,

  DELETE = function(self, dao_factory)
    crud.delete(self.credential, dao_factory.basicauth_credentials)
  end
}

return {
  ["/consumers/:username_or_id/basic-auth/"] = global_route,
  ["/consumers/:username_or_id/basic-auth/:id"] = single_route,
  -- Deprecated in 0.5.0, maintained for backwards compatibility.
  ["/consumers/:username_or_id/basicauth/"] = global_route,
  ["/consumers/:username_or_id/basicauth/:id"] = single_route
}
