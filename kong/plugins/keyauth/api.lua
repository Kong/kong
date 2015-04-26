-- Copyright (C) Mashape, Inc.

local BaseController = require "kong.api.routes.base_controller"

local KeyAuthCredentials = BaseController:extend()

function KeyAuthCredentials:new()
  KeyAuthCredentials.super.new(self, dao.keyauth_credentials, "keyauth_credentials")
end

return KeyAuthCredentials
