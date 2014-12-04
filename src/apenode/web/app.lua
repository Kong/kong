-- Copyright (C) Mashape, Inc.

local lapis = require "lapis"
local utils = require "apenode.core.utils"

app = lapis.Application()

require "apenode.web.apis"
require "apenode.web.applications"

app:get("/", function(self)
  return utils.success("Welcome to Apenode")
end)

return app