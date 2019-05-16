-- Copyright (C) Kong Inc.
local access = require "kong.plugins.basic-auth.access"


local BasicAuthHandler = {}


function BasicAuthHandler:access(conf)
  access.execute(conf)
end


BasicAuthHandler.PRIORITY = 1001
BasicAuthHandler.VERSION = "2.0.0"


return BasicAuthHandler
