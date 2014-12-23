-- Copyright (C) Mashape, Inc.

local BasePlugin = require "apenode.base_plugin"
local access = require "apenode.plugins.authentication.access"
local stringy = require "stringy"

local function check_authentication_type(v)
  if v and (v == "query" or v == "header" or v == "basic") then
    return true
  else
    return false, "Only \"query\", \"header\" or \"basic\" authentication types are supported"
  end
end

local function check_authentication_key_names(v, t)
  if t.authentication_type and t.authentication_type ~= "basic" and v and utils.table_size(v) > 0 then
    return true
  else
    return false, "You need to specify a query or header name for this authentication type"
  end
end

local AuthenticationHandler = BasePlugin:extend()

AuthenticationHandler["_SCHEMA"] = {
  authentication_type = { type = "string", required = true, func = check_authentication_type },
  authentication_key_names = { type = "table", func = check_authentication_key_names },
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
