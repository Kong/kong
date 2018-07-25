local access = require "kong.plugins.ldap-auth-windows.access"
local BasePlugin = require "kong.plugins.base_plugin"

local LdapAuthHandler = BasePlugin:extend()

function LdapAuthHandler:new()
  LdapAuthHandler.super.new(self, "ldap-auth-windows")
end

function LdapAuthHandler:access(conf)
  LdapAuthHandler.super.access(self)
  access.execute(conf)
end

LdapAuthHandler.PRIORITY = 1002
LdapAuthHandler.VERSION = "0.1.0"

return LdapAuthHandler
