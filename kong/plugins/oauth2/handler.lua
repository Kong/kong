local access = require "kong.plugins.oauth2.access"


local OAuthHandler = {
  PRIORITY = 1004,
  VERSION = "2.2.0",
}


function OAuthHandler:access(conf)
  access.execute(conf)
end


return OAuthHandler
