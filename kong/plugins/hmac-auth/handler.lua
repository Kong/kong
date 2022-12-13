-- Copyright (C) Kong Inc.
local access = require "kong.plugins.hmac-auth.access"
local kong_meta = require "kong.meta"


local HMACAuthHandler = {
  VERSION = kong_meta.version,
  PRIORITY = 1030,
}


function HMACAuthHandler:access(conf)
  access.execute(conf)
end


return HMACAuthHandler
