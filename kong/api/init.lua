local lapis       = require "lapis"
local utils       = require "kong.tools.utils"
local singletons  = require "kong.singletons"
local api_helpers = require "kong.api.api_helpers"
local Endpoints   = require "kong.api.endpoints"


local ngx      = ngx
local type     = type
local pairs    = pairs
local ipairs   = ipairs


local app = lapis.Application()


app.default_route = api_helpers.default_route
app.handle_404 = api_helpers.handle_404
app.handle_error = api_helpers.handle_error
app:before_filter(api_helpers.before_filter)


ngx.log(ngx.DEBUG, "Loading Admin API endpoints")


-- Load core routes
for _, v in ipairs({"kong", "health", "cache", "config"}) do
  local routes = require("kong.api.routes." .. v)
  api_helpers.attach_routes(app, routes)
end


do
  local routes = {}

  -- Auto Generated Routes
  for _, dao in pairs(singletons.db.daos) do
    if dao.schema.generate_admin_api ~= false and not dao.schema.legacy then
      routes = Endpoints.new(dao.schema, routes)
    end
  end

  -- Custom Routes
  for _, dao in pairs(singletons.db.daos) do
    local schema = dao.schema

    local ok, custom_endpoints = utils.load_module_if_exists("kong.api.routes." .. schema.name)
    if ok then
      for route_pattern, verbs in pairs(custom_endpoints) do
        if routes[route_pattern] ~= nil and type(verbs) == "table" then
          for verb, handler in pairs(verbs) do
            local parent = routes[route_pattern]["methods"][verb]
            if parent ~= nil and type(handler) == "function" then
              routes[route_pattern]["methods"][verb] = function(self, db, helpers)
                return handler(self, db, helpers, function(post_process)
                  return parent(self, db, helpers, post_process)
                end)
              end

            else
              routes[route_pattern]["methods"][verb] = handler
            end
          end

        else
          routes[route_pattern] = {
            schema  = dao.schema,
            methods = verbs,
          }
        end
      end
    end
  end

  api_helpers.attach_new_db_routes(app, routes)
end


local function is_new_db_routes(mod)
  for _, verbs in pairs(mod) do
    if type(verbs) == "table" then -- ignore "before" functions
      return verbs.schema
    end
  end
end


-- Loading plugins routes
if singletons.configuration and singletons.configuration.loaded_plugins then
  for k in pairs(singletons.configuration.loaded_plugins) do
    local loaded, mod = utils.load_module_if_exists("kong.plugins." .. k .. ".api")

    if loaded then
      ngx.log(ngx.DEBUG, "Loading API endpoints for plugin: ", k)
      if is_new_db_routes(mod) then
        api_helpers.attach_new_db_routes(app, mod)
      else
        api_helpers.attach_routes(app, mod)
      end

    else
      ngx.log(ngx.DEBUG, "No API endpoints loaded for plugin: ", k)
    end
  end
end


return app
