local access = require "kong.plugins.ldap-auth-advanced.access"
local BasePlugin = require "kong.plugins.base_plugin"
local ldap_cache = require "kong.plugins.ldap-auth-advanced.cache"

local LdapAuthHandler = BasePlugin:extend()

function LdapAuthHandler:new()
  LdapAuthHandler.super.new(self, "ldap-auth-advanced")
end

function LdapAuthHandler:access(conf)
  LdapAuthHandler.super.access(self)
  access.execute(conf)
end

function LdapAuthHandler:init_worker()
  LdapAuthHandler.super.init_worker(self)
  ldap_cache.init_worker()
end

LdapAuthHandler.PRIORITY = 1002
LdapAuthHandler.VERSION = "1.0.0"

return LdapAuthHandler
