-- Copyright (C) Kong Inc.
local access = require "kong.plugins.basic-auth.access"
local kong_meta = require "kong.meta"

local BasicAuthHandler = {
  VERSION = kong_meta.version,
  PRIORITY = 1100,
}


function BasicAuthHandler:access(conf)
  access.execute(conf)
end

return BasicAuthHandler
