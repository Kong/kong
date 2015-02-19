local constants = require "kong.constants"
local lapis = require "lapis"
local Apis = require "kong.web.routes.apis"
local Plugins = require "kong.web.routes.plugins"
local Accounts = require "kong.web.routes.accounts"
local Applications = require "kong.web.routes.applications"

app = lapis.Application()

app:get("/", function(self)
  return utils.success({
    tagline = "Welcome to Kong",
    version = constants.VERSION
  })
end)

app.handle_404 = function(self)
  return utils.not_found()
end

-- Load controllers
Apis()
Accounts()
Applications()
Plugins()

return app
