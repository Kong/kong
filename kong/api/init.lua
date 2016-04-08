local lapis = require "lapis"
local utils = require "kong.tools.utils"
local stringy = require "stringy"
local responses = require "kong.tools.responses"
local singletons = require "kong.singletons"
local app_helpers = require "lapis.application"
local api_helpers = require "kong.api.api_helpers"

local find = string.find

local app = lapis.Application()

local function parse_params(fn)
  return app_helpers.json_params(function(self, ...)
    local content_type = self.req.headers["content-type"]
    if content_type and find(content_type:lower(), "application/json", nil, true) then
      if not self.json then
        return responses.send_HTTP_BAD_REQUEST("Cannot parse JSON body")
      end
    end
    self.params = api_helpers.normalize_nested_params(self.params)
    return fn(self, ...)
  end)
end

local function on_error(self)
  local err = self.errors[1]
  if type(err) == "table" then
    if err.db then
      return responses.send_HTTP_INTERNAL_SERVER_ERROR(err.message)
    elseif err.unique then
      return responses.send_HTTP_CONFLICT(err.tbl)
    elseif err.foreign then
      return responses.send_HTTP_NOT_FOUND(err.tbl)
    else
      return responses.send_HTTP_BAD_REQUEST(err.tbl or err.message)
    end
  end
end

app.default_route = function(self)
  local path = self.req.parsed_url.path:match("^(.*)/$")

  if path and self.app.router:resolve(path, self) then
    return
  elseif self.app.router:resolve(self.req.parsed_url.path.."/", self) then
    return
  end

  return self.app.handle_404(self)
end

app.handle_404 = function(self)
  return responses.send_HTTP_NOT_FOUND()
end

app.handle_error = function(self, err, trace)
  if stringy.find(err, "don't know how to respond to") ~= nil then
    return responses.send_HTTP_METHOD_NOT_ALLOWED()
  else
    ngx.log(ngx.ERR, err.."\n"..trace)
  end

  -- We just logged the error so no need to give it to responses and log it twice
  return responses.send_HTTP_INTERNAL_SERVER_ERROR()
end

app:before_filter(function(self)
  local method = ngx.req.get_method()
  if method ~= "GET" and method ~= "DELETE" then
    local content_type = self.req.headers["content-type"]
    if not content_type or stringy.strip(content_type) == "" then
      return responses.send_HTTP_UNSUPPORTED_MEDIA_TYPE()
    end
  end
end)

local handler_helpers = {
  responses = responses,
  yield_error = app_helpers.yield_error
}

local function attach_routes(routes)
  for route_path, methods in pairs(routes) do
    if not methods.on_error then
      methods.on_error = on_error
    end

    for k, v in pairs(methods) do
      local method = function(self)
        return v(self, singletons.dao, handler_helpers)
      end
      methods[k] = parse_params(method)
    end

    app:match(route_path, route_path, app_helpers.respond_to(methods))
  end
end

-- Load core routes
for _, v in ipairs({"kong", "apis", "consumers", "plugins", "cache", "cluster" }) do
  local routes = require("kong.api.routes."..v)
  attach_routes(routes)
end

-- Loading plugins routes
if singletons.configuration and singletons.configuration.plugins then
  for _, v in ipairs(singletons.configuration.plugins) do
    local loaded, mod = utils.load_module_if_exists("kong.plugins."..v..".api")
    if loaded then
      ngx.log(ngx.DEBUG, "Loading API endpoints for plugin: "..v)
      attach_routes(mod)
    else
      ngx.log(ngx.DEBUG, "No API endpoints loaded for plugin: "..v)
    end
  end
end

return app
