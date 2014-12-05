-- Copyright (C) Mashape, Inc.

local lapis = require "lapis"
local utils = require "apenode.core.utils"
local Apis = require "apenode.web.apis"
local Applications = require "apenode.web.applications"

app = lapis.Application()

app:get("/", function(self)
  return utils.success({
    tagline = "Welcome to Apenode",
    version = configuration.version
  })
end)

app.handle_404 = function(self)
  return utils.not_found()
end

-- Load controllers
Apis()
Applications()

return app