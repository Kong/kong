-- Copyright (C) Kong Inc.
local access = require "kong.plugins.basic-auth-v2.access"


local BasicAuthHandler = {
  PRIORITY = 1001,
  VERSION = "1.0.0",
}


function BasicAuthHandler:access(conf)
  access.execute(conf)
end


return BasicAuthHandler
