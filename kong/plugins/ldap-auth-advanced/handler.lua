local access = require "kong.plugins.ldap-auth-advanced.access"
local ldap_cache = require "kong.plugins.ldap-auth-advanced.cache"


local LdapAuthHandler = {}


function LdapAuthHandler:access(conf)
  access.execute(conf)
end


function LdapAuthHandler:init_worker()
  ldap_cache.init_worker()
end


LdapAuthHandler.PRIORITY = 1002
LdapAuthHandler.VERSION = "1.0.0"


return LdapAuthHandler
