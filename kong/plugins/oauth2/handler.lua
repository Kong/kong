local access = require "kong.plugins.oauth2.access"
local kong_meta = require "kong.meta"


local OAuthHandler = {
  PRIORITY = 1004,
  VERSION = kong_meta._VERSION,
}


function OAuthHandler:access(conf)
  access.execute(conf)
end


return OAuthHandler
