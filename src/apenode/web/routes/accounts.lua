-- Copyright (C) Mashape, Inc.

local app_helpers = require "lapis.application"
local validate = require "lapis.validate"
local capture_errors, yield_error = app_helpers.capture_errors, app_helpers.yield_error

local BaseController = require "apenode.web.routes.base_controller"

local Accounts = {}
Accounts.__index = Accounts

setmetatable(Accounts, {
  __index = BaseController, -- this is what makes the inheritance work
  __call = function (cls, ...)
    local self = setmetatable({}, cls)
    self:_init(...)
    return self
  end,
})

validate.validate_functions.provider_id_exists = function(input)
  if dao.accounts:get_by_provider_id(input) then
    return false, "%s already exists"
  else
    return true
  end
end

function Accounts:_init()
  BaseController:_init(constants.ACCOUNTS_COLLECTION) -- call the base class constructor

  app:post("/" .. constants.ACCOUNTS_COLLECTION .. "/", capture_errors({
    on_error = function(self)
      return utils.show_error(400, self.errors)
    end,
    function(self)
      validate.assert_valid(self.params, {
        { "provider_id", provider_id_exists = true }
      })

      local account = dao.accounts:save({
        provider_id = self.params.provider_id
      })

      return utils.created(account)
    end
  }))
end

return Accounts