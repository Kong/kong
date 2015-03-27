-- Copyright (C) Mashape, Inc.

local BaseController = require "kong.web.routes.base_controller"

local BasicAuthCredentials = BaseController:extend()

function BasicAuthCredentials:new()
  BasicAuthCredentials.super.new(self, dao.basicauth_credentials, "basicauth_credentials")
end

return BasicAuthCredentials
