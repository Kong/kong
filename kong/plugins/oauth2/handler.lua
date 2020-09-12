local access = require "kong.plugins.oauth2.access"


local OAuthHandler = {
  PRIORITY = 1004,
  VERSION = "2.1.1",
}


function OAuthHandler:access(conf)
  access.execute(conf)
end


return OAuthHandler
