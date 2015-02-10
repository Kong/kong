-- Copyright (C) Mashape, Inc.

local lapis = require "lapis"
local Apis = require "kong.web.routes.apis"
local Plugins = require "kong.web.routes.plugins"
local Accounts = require "kong.web.routes.accounts"
local Applications = require "kong.web.routes.applications"

app = lapis.Application()

-- Handle index
app:get("/", function(self)
  return utils.success({
    tagline = "Welcome to Kong",
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
