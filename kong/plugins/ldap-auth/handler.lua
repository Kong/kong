local access = require "kong.plugins.ldap-auth.access"


local LdapAuthHandler = {
  PRIORITY = 1002,
  VERSION = "2.2.0",
}


function LdapAuthHandler:access(conf)
  access.execute(conf)
end


return LdapAuthHandler
