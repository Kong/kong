-- Copyright (C) Kong Inc.
local access = require "kong.plugins.hmac-auth.access"


local HMACAuthHandler = {
  PRIORITY = 1000,
  VERSION = "2.4.0",
}


function HMACAuthHandler:access(conf)
  access.execute(conf)
end


return HMACAuthHandler
