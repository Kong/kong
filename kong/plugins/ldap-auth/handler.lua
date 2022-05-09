local access = require "kong.plugins.ldap-auth.access"
local kong_meta = require "kong.meta"


local LdapAuthHandler = {
  PRIORITY = 1002,
  VERSION = kong_meta._VERSION,
}


function LdapAuthHandler:access(conf)
  access.execute(conf)
end


return LdapAuthHandler
