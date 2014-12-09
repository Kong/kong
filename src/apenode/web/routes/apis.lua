-- Copyright (C) Mashape, Inc.

local stringy = require "stringy"
local app_helpers = require "lapis.application"
local validate = require "lapis.validate"
local capture_errors, yield_error = app_helpers.capture_errors, app_helpers.yield_error

local BaseController = require "apenode.web.routes.base_controller"

local Apis = {}
Apis.__index = Apis

setmetatable(Apis, {
  __index = BaseController, -- this is what makes the inheritance work
  __call = function (cls, ...)
    local self = setmetatable({}, cls)
    self:_init(...)
    return self
  end,
})

validate.validate_functions.public_dns_exists = function(input)
  if dao.apis:get_by_host(input) then
    return false, "%s already exists"
  else
    return true
  end
end

validate.validate_functions.is_dns = function(input)
  local m, err = ngx.re.match(input, "(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\\-]*[a-zA-Z0-9])\\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\\-]*[A-Za-z0-9])")
  if m then
    return true
  else
    return false, "%s must be a valid dns name"
  end
end

function Apis:_init()
  BaseController:_init(constants.APIS_COLLECTION) -- call the base class constructor

  app:post("/" .. constants.APIS_COLLECTION .. "/", capture_errors({
    on_error = function(self)
      return utils.show_error(400, self.errors)
    end,
    function(self)
      validate.assert_valid(self.params, {
        { "public_dns", exists = true, is_dns = true, public_dns_exists = true },
        { "target_url", exists = true, min_length = 8, "Invalid target_url" },
        { "authentication_type", exists = true, one_of = { "query", "header", "basic" }, "Invalid authentication_type" },
        { "authentication_key_names", exists = true, min_length = 1 }
      })

      local api = dao.apis:save({
        public_dns = self.params.public_dns,
        target_url = self.params.target_url,
        authentication_type = self.params.authentication_type,
        authentication_key_names = stringy.split(self.params.authentication_key_names, ",")
      })

      return utils.created(api)
    end
  }))
end

return Apis