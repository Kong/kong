-- Copyright (C) Kong Inc.
local access = require "kong.plugins.basic-auth.access"


local BasicAuthHandler = {}


function BasicAuthHandler:access(conf, exit_handler)
  ---EE [[
  return access.execute(conf, exit_handler)
  --]] EE
end


BasicAuthHandler.PRIORITY = 1001
BasicAuthHandler.VERSION = "2.0.0"


return BasicAuthHandler
