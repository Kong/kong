-- Copyright (C) Mashape, Inc.

local lapis = require "lapis"
local utils = require "apenode.core.utils"

app = lapis.Application()

app:get("/", function(self)
  return utils.show_response(200, "Welcome to Apenode")
end)

require "apenode.web.apis"
require "apenode.web.applications"

return app