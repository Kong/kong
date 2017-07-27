local access = require "kong.plugins.ldap-auth.access"
local BasePlugin = require "kong.plugins.base_plugin"

local LdapAuthHandler = BasePlugin:extend()

function LdapAuthHandler:new()
  LdapAuthHandler.super.new(self, "ldap-auth")
end

function LdapAuthHandler:access(conf)
  LdapAuthHandler.super.access(self)
  access.execute(conf)
end

LdapAuthHandler.PRIORITY = 1500

return LdapAuthHandler
