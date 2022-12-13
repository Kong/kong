local access = require "kong.plugins.ldap-auth.access"
local kong_meta = require "kong.meta"


local LdapAuthHandler = {
  VERSION = kong_meta.version,
  PRIORITY = 1200,
}


function LdapAuthHandler:access(conf)
  access.execute(conf)
end


return LdapAuthHandler
