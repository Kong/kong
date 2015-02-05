-- Copyright (C) Mashape, Inc.

local lapis = require "lapis"
local Apis = require "apenode.web.routes.apis"
local Plugins = require "apenode.web.routes.plugins"
local Accounts = require "apenode.web.routes.accounts"
local Applications = require "apenode.web.routes.applications"

app = lapis.Application()

-- Handle index
app:get("/", function(self)
  return utils.success({
    tagline = "Welcome to Apenode",
    version = configuration.version
  })
end)

-- Handle 404 page
app.handle_404 = function(self)
  return utils.not_found()
end

-- Load controllers
Apis()
Accounts()
Applications()
Plugins()

return app
