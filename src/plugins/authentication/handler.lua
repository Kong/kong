-- Copyright (C) Mashape, Inc.

local BasePlugin = require "kong.plugins.base_plugin"
local access = require "kong.plugins.authentication.access"

local AuthenticationHandler = BasePlugin:extend()

function AuthenticationHandler:new()
  AuthenticationHandler.super.new(self, "authentication")
end

function AuthenticationHandler:access(conf)
  AuthenticationHandler.super.access(self)
  access.execute(conf)
end

AuthenticationHandler.PRIORITY = 1000

return AuthenticationHandler
