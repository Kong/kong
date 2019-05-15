local access = require "kong.plugins.oauth2.access"

local OAuthHandler = {}

function OAuthHandler:access(conf)
  access.execute(conf)
end

OAuthHandler.PRIORITY = 1004
OAuthHandler.VERSION = "2.0.0"

return OAuthHandler
