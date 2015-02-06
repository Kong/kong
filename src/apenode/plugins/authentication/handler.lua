-- Copyright (C) Mashape, Inc.

local BasePlugin = require "apenode.base_plugin"
local access = require "apenode.plugins.authentication.access"
local stringy = require "stringy"
local utils = require "apenode.tools.utils"

-------------
-- PRIVATE --
-------------

local function check_authentication_type(v)
  if v and (v == "query" or v == "header" or v == "basic") then
    return true
  else
    return false, "Only \"query\", \"header\" or \"basic\" authentication types are supported"
  end
end

local function check_authentication_key_names(names, plugin_value)
  if names and type(names) ~= "table" then
    return false, "You need to specify an array"
  end

  if plugin_value.authentication_type == "basic" or names and utils.table_size(names) > 0 then
    return true
  else
    return false, "You need to specify a query or header name for this authentication type"
  end
end

-------------
-- Handler --
-------------

local AuthenticationHandler = BasePlugin:extend()

local SCHEMA = {
  authentication_type = { type = "string", required = true, enum = {"query", "basic", "header"} },
  authentication_key_names = { type = "table", required = true },
  hide_credentials = { type = "boolean", default = false }
}

function AuthenticationHandler:new()
  self._schema = SCHEMA
  AuthenticationHandler.super.new(self, "authentication")
end

function AuthenticationHandler:access(conf)
  AuthenticationHandler.super.access(self)
  access.execute(conf)
end

return AuthenticationHandler
