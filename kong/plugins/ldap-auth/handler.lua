local access = require "kong.plugins.ldap-auth.access"


local LdapAuthHandler = {}


function LdapAuthHandler:access(conf)
  access.execute(conf)
end


LdapAuthHandler.PRIORITY = 1002
LdapAuthHandler.VERSION = "1.0.0"


return LdapAuthHandler
