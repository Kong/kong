local lapis       = require "lapis"
local utils       = require "kong.tools.utils"
local singletons  = require "kong.singletons"
local api_helpers = require "kong.api.api_helpers"


local ngx      = ngx
local pairs    = pairs


local app = lapis.Application()


app.default_route = api_helpers.default_route
app.handle_404 = api_helpers.handle_404
app.handle_error = api_helpers.handle_error
app:before_filter(api_helpers.before_filter)


ngx.log(ngx.DEBUG, "Loading Status API endpoints")


-- Load core health route
api_helpers.attach_routes(app, require "kong.api.routes.health")


-- Load plugins status routes
if singletons.configuration and singletons.configuration.loaded_plugins then
  for k in pairs(singletons.configuration.loaded_plugins) do
    local loaded, mod = utils.load_module_if_exists("kong.plugins." ..
                                                    k .. ".status_api")

    if loaded then
      ngx.log(ngx.DEBUG, "Loading Status API endpoints for plugin: ", k)
      api_helpers.attach_routes(app, mod)
    else
      ngx.log(ngx.DEBUG, "No Status API endpoints loaded for plugin: ", k)
    end
  end
end


return app
