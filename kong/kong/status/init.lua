local lapis       = require "lapis"
local api_helpers = require "kong.api.api_helpers"
local hooks       = require "kong.hooks"
local load_module_if_exists = require "kong.tools.module".load_module_if_exists


local ngx = ngx
local kong = kong
local pairs = pairs


local app = lapis.Application()


app.default_route = api_helpers.default_route
app.handle_404 = api_helpers.handle_404
app.handle_error = api_helpers.handle_error
app:before_filter(api_helpers.before_filter)

-- Hooks for running before_filter similar to kong/api
assert(hooks.run_hook("status_api:init:pre", app))


ngx.log(ngx.DEBUG, "Loading Status API endpoints")


-- Load core health route
api_helpers.attach_routes(app, require "kong.api.routes.health")
api_helpers.attach_routes(app, require "kong.status.ready")
api_helpers.attach_routes(app, require "kong.api.routes.dns")


if kong.configuration.database == "off" then
  -- Load core upstream readonly routes
  -- Customized routes in upstreams doesn't call `parent`, otherwise we will need
  -- api/init.lua:customize_routes to pass `parent`.
  local upstream_routes = {}
  for route_path, definition in pairs(require "kong.api.routes.upstreams") do
    local method_handlers = {}
    local has_methods
    for method_name, method_handler in pairs(definition) do
      if method_name:upper() == "GET" then
        has_methods = true
        method_handlers[method_name] = method_handler
      end
    end

    if has_methods then
      upstream_routes[route_path] = {
        schema = kong.db.upstreams.schema,
        methods = method_handlers,
      }
    end
  end

  api_helpers.attach_new_db_routes(app, upstream_routes)
end

-- Load plugins status routes
if kong.configuration and kong.configuration.loaded_plugins then
  for k in pairs(kong.configuration.loaded_plugins) do
    local loaded, mod = load_module_if_exists("kong.plugins." ..
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
