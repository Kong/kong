-- Copyright (C) Kong Inc.
local access = require "kong.plugins.hmac-auth.access"
local kong_meta = require "kong.meta"


local HMACAuthHandler = {
  PRIORITY = 1000,
  VERSION = kong_meta._VERSION,
}


function HMACAuthHandler:access(conf)
  access.execute(conf)
end


return HMACAuthHandler
