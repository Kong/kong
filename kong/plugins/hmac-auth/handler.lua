-- Copyright (C) Kong Inc.
local access = require "kong.plugins.hmac-auth.access"


local HMACAuthHandler = {}


function HMACAuthHandler:access(conf)
  access.execute(conf)
end


HMACAuthHandler.PRIORITY = 1000
HMACAuthHandler.VERSION = "1.0.0"


return HMACAuthHandler
