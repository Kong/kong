local access = require "kong.plugins.oauth2.access"
local kong_meta = require "kong.meta"


local OAuthHandler = {
  VERSION = kong_meta.version,
  PRIORITY = 1400,
}


function OAuthHandler:access(conf)
  access.execute(conf)
end


return OAuthHandler
