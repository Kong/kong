local constants = require "kong.constants"
local utils = require "kong.tools.utils"
local lapis = require "lapis"
local Apis = require "kong.web.routes.apis"
local Plugins = require "kong.web.routes.plugins"
local Accounts = require "kong.web.routes.accounts"
local Applications = require "kong.web.routes.applications"

app = lapis.Application()

app:get("/", function(self)

  local db_plugins, err = dao.plugins:find_distinct()
  if err then
    ngx.log(ngx.ERR, err)
    return utils.show_error(500, err)
  end

  return utils.success({
    tagline = "Welcome to Kong",
    version = constants.VERSION,
    hostname = utils.get_hostname(),
    plugins = {
      available_on_server = plugins_available,
      enabled_in_cluster = db_plugins
    }
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
