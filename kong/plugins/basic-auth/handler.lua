-- Copyright (C) Kong Inc.
local access = require "kong.plugins.basic-auth.access"
local kong_meta = require "kong.meta"

local BasicAuthHandler = {
  PRIORITY = 1001,
  VERSION = kong_meta._VERSION,
}


function BasicAuthHandler:access(conf)
  access.execute(conf)
end

return BasicAuthHandler
