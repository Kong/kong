-- Copyright (C) Kong Inc.
local access = require "kong.plugins.basic-auth.access"


local BasicAuthHandler = {
  PRIORITY = 1001,
  VERSION = "2.2.0",
}


function BasicAuthHandler:access(conf, exit_handler)
  ---EE [[
  return access.execute(conf, exit_handler)
  --]] EE
end


return BasicAuthHandler
