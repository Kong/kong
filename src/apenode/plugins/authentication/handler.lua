-- Copyright (C) Mashape, Inc.

local BasePlugin = require "apenode.base_plugin"
local access = require "apenode.plugins.authentication.access"

local AuthenticationHandler = BasePlugin:extend()

AuthenticationHandler["_SCHEMA"] = {
  authentication_type = { type = "string", required = true },
  authentication_key_names = { type = "table" },
  hide_credentials = { type = "boolean", required = true }
}

function AuthenticationHandler:new()
  AuthenticationHandler.super.new(self, "authentication")
end

function AuthenticationHandler:access(conf)
  AuthenticationHandler.super.access(self)
  access.execute(conf)
end

return AuthenticationHandler
