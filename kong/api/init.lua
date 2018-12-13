local lapis       = require "lapis"
local utils       = require "kong.tools.utils"
local tablex      = require "pl.tablex"
local pl_pretty   = require "pl.pretty"
local singletons  = require "kong.singletons"
local app_helpers = require "lapis.application"
local api_helpers = require "kong.api.api_helpers"
local Endpoints   = require "kong.api.endpoints"
local arguments   = require "kong.api.arguments"
local Errors      = require "kong.db.errors"


local ngx      = ngx
local sub      = string.sub
local find     = string.find
local type     = type
local pairs    = pairs
local ipairs   = ipairs


local app = lapis.Application()


local NEEDS_BODY = tablex.readonly({ PUT = 1, POST = 2, PATCH = 3 })


local function parse_params(fn)
  return app_helpers.json_params(function(self, ...)
    if NEEDS_BODY[ngx.req.get_method()] then
      local content_type = self.req.headers["content-type"]
      if content_type then
        content_type = content_type:lower()

        if find(content_type, "application/json", 1, true) and not self.json then
          return kong.response.exit(400, { message = "Cannot parse JSON body" })

        elseif find(content_type, "application/x-www-form-urlencode", 1, true) then
          self.params = utils.decode_args(self.params)
        end
      end
    end

    self.params = api_helpers.normalize_nested_params(self.params)

    local res = fn(self, ...)
    if res == nil and ngx.status >= 200 then
      return ngx.exit(0)
    end

    return res
  end)
end


-- new DB
local function new_db_on_error(self)
  local err = self.errors[1]

  if type(err) ~= "table" then
    kong.log.err(err)
    return kong.response.exit(500, { message = "An unexpected error occurred" })
  end

  if err.strategy then
    err.strategy = nil
  end

  if err.code == Errors.codes.SCHEMA_VIOLATION
  or err.code == Errors.codes.INVALID_PRIMARY_KEY
  or err.code == Errors.codes.FOREIGN_KEY_VIOLATION
  or err.code == Errors.codes.INVALID_OFFSET
  then
    return kong.response.exit(400, err)
  end

  if err.code == Errors.codes.NOT_FOUND then
    return kong.response.exit(404, err)
  end

  if err.code == Errors.codes.PRIMARY_KEY_VIOLATION
  or err.code == Errors.codes.UNIQUE_VIOLATION
  then
    return kong.response.exit(409, err)
  end

  kong.log.err(err)
  return kong.response.exit(500, { message = "An unexpected error occurred" })
end


-- old DAO
local function on_error(self)
  local err = self.errors[1]

  if type(err) ~= "table" then
    kong.log.err(err)
    return kong.response.exit(500, { message = "An unexpected error occurred" })
  end

  if err.name then
    return new_db_on_error(self)
  end

  if err.db then
    kong.log.err(err.message)
    return kong.response.exit(500, { message = "An unexpected error occurred" })
  end

  if err.unique then
    return kong.response.exit(409, err.tbl)
  end

  if err.foreign then
    return kong.response.exit(404, err.tbl or { message = "Not found" })
  end

  return kong.response.exit(400, err.tbl or err.message)
end


app.default_route = function(self)
  local path = self.req.parsed_url.path:match("^(.*)/$")

  if path and self.app.router:resolve(path, self) then
    return

  elseif self.app.router:resolve(self.req.parsed_url.path .. "/", self) then
    return
  end

  return self.app.handle_404(self)
end


app.handle_404 = function(self)
  return kong.response.exit(404, { message = "Not found" })
end


app.handle_error = function(self, err, trace)
  if err then
    if type(err) ~= "string" then
      err = pl_pretty.write(err)
    end
    if find(err, "don't know how to respond to", nil, true) then
      return kong.response.exit(405, { message = "Method not allowed" })
    end
  end

  ngx.log(ngx.ERR, err, "\n", trace)

  -- We just logged the error so no need to give it to responses and log it
  -- twice
  return kong.response.exit(500, { message = "An unexpected error occurred" })
end


app:before_filter(function(self)
  if not NEEDS_BODY[ngx.req.get_method()] then
    return
  end

  local content_type = self.req.headers["content-type"]
  if not content_type then
    local content_length = self.req.headers["content-length"]
    if content_length == "0" then
      return
    end

    if not content_length then
      local _, err = ngx.req.socket()
      if err == "no body" then
        return
      end
    end

  elseif sub(content_type, 1, 16) == "application/json"                  or
         sub(content_type, 1, 19) == "multipart/form-data"               or
         sub(content_type, 1, 33) == "application/x-www-form-urlencoded" then
    return
  end

  return kong.response.exit(415)
end)


local handler_helpers = {
  yield_error = app_helpers.yield_error
}


local function attach_routes(routes)
  for route_path, methods in pairs(routes) do
    methods.on_error = methods.on_error or on_error

    for method_name, method_handler in pairs(methods) do
      local wrapped_handler = function(self)
        return method_handler(self, singletons.dao, handler_helpers)
      end

      methods[method_name] = parse_params(wrapped_handler)
    end

    app:match(route_path, route_path, app_helpers.respond_to(methods))
  end
end


local function attach_new_db_routes(routes)
  for route_path, definition in pairs(routes) do
    local schema  = definition.schema
    local methods = definition.methods

    methods.on_error = methods.on_error or new_db_on_error

    for method_name, method_handler in pairs(methods) do
      local wrapped_handler = function(self)
        self.args = arguments.load({
          schema  = schema,
          request = self.req,
        })

        return method_handler(self, singletons.db, handler_helpers)
      end

      methods[method_name] = parse_params(wrapped_handler)
    end

    app:match(route_path, route_path, app_helpers.respond_to(methods))
  end
end


ngx.log(ngx.DEBUG, "Loading Admin API endpoints")


-- Load core routes
for _, v in ipairs({"kong", "apis", "cache"}) do
  local routes = require("kong.api.routes." .. v)
  attach_routes(routes)
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

  attach_new_db_routes(routes)
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
        attach_new_db_routes(mod)
      else
        attach_routes(mod)
      end

    else
      ngx.log(ngx.DEBUG, "No API endpoints loaded for plugin: ", k)
    end
  end
end


return app
