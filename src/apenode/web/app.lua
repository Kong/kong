-- Copyright (C) Mashape, Inc.

local lapis = require "lapis"
local Accounts = require "apenode.web.routes.accounts"
local Apis = require "apenode.web.routes.apis"
local Applications = require "apenode.web.routes.applications"

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
Accounts()
Applications()
Apis()

return app