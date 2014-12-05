-- Copyright (C) Mashape, Inc.

local constants = require "apenode.constants"
local utils = require "apenode.utils"
local app_helpers = require "lapis.application"
local validate = require "lapis.validate"
local capture_errors, yield_error = app_helpers.capture_errors, app_helpers.yield_error

local BaseController = require "apenode.web.base_controller"

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

function Apis:_init()
  BaseController._init(self, constants.APIS_COLLECTION) -- call the base class constructor

  app:post("/" .. constants.APIS_COLLECTION .. "/", capture_errors({
    on_error = function(self)
      return utils.show_error(400, self.errors)
    end,
    function(self)
      validate.assert_valid(self.params, {
        { "public_dns", exists = true, min_length = 1, "Invalid public_dns" },
        { "target_url", exists = true, min_length = 1, "Invalid target_url" },
        { "authentication_type", exists = true, one_of = { "query", "header", "basic"}, "Invalid authentication_type" }
      })

      local api = dao.apis:save({
        public_dns = self.params.public_dns,
        target_url = self.params.target_url,
        authentication_type = self.params.authentication_type,
        authentication_key_names =  { "apikey", "cazzo" }
      })

      return utils.created(api)
    end
  }))
end

return Apis