-- Copyright (C) Kong Inc.
local access = require "kong.plugins.hmac-auth.access"


local HMACAuthHandler = {
  PRIORITY = 1000,
  VERSION = "2.2.1",
}


function HMACAuthHandler:access(conf)
  access.execute(conf)
end


return HMACAuthHandler
