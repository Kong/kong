-- Copyright (C) Mashape, Inc.

local app_helpers = require "lapis.application"
local validate = require "lapis.validate"
local capture_errors, yield_error = app_helpers.capture_errors, app_helpers.yield_error

local BaseController = require "apenode.web.routes.base_controller"

local Applications = {}
Applications.__index = Applications

setmetatable(Applications, {
  __index = BaseController, -- this is what makes the inheritance work
  __call = function (cls, ...)
    local self = setmetatable({}, cls)
    self:_init(...)
    return self
  end,
})

validate.validate_functions.account_exists = function(input)
  if dao.accounts:get_by_id(input) then
    return true
  else
    return false, "account %s not found"
  end
end

function Applications:_init()
  BaseController:_init(constants.APPLICATIONS_COLLECTION) -- call the base class constructor

  app:post("/" .. constants.APPLICATIONS_COLLECTION .. "/", capture_errors({
    on_error = function(self)
      return utils.show_error(400, self.errors)
    end,
    function(self)
      validate.assert_valid(self.params, {
        { "secret_key", exists = true, min_length = 1, "Invalid secret_key" },
        { "account_id", exists = true, account_exists = true }
      })

      if dao.applications:get_by_key(self.params.public_key, self.params.secret_key) then
        return utils.show_error(400, { "An application with the same keys already exist" })
      end

      local application = dao.applications:save({
        account_id = self.params.account_id,
        public_key = self.params.public_key,
        secret_key = self.params.secret_key
      })

      return utils.created(application)
    end
  }))
end

return Applications