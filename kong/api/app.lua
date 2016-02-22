local singletons = require "kong.singletons"
local lapis = require "lapis"
local utils = require "kong.tools.utils"
local stringy = require "stringy"
local responses = require "kong.tools.responses"
local app_helpers = require "lapis.application"
local app = lapis.Application()

-- Parses a form value, handling multipart/data values
-- @param `v` The value object
-- @return The parsed value
local function parse_value(v)
  return type(v) == "table" and v.content or v -- Handle multipart
end

-- Put nested keys in objects:
-- Normalize dotted keys in objects.
-- Example: {["key.value.sub"]=1234} becomes {key = {value = {sub=1234}}
-- @param `obj` Object to normalize
-- @return `normalized_object`
local function normalize_nested_params(obj)
  local new_obj = {}

  local function attach_dotted_key(keys, attach_to, value)
    local current_key = keys[1]

    if #keys > 1 then
      if not attach_to[current_key] then
        attach_to[current_key] = {}
      end
      table.remove(keys, 1)
      attach_dotted_key(keys, attach_to[current_key], value)
    else
      attach_to[current_key] = value
    end
  end

  for k, v in pairs(obj) do
    if type(v) == "table" then
      -- normalize arrays since Lapis parses ?key[1]=foo as {["1"]="foo"} instead of {"foo"}
      if utils.is_array(v) then
        local arr = {}
        for _, arr_v in pairs(v) do table.insert(arr, arr_v) end
        v = arr
      else
        v = normalize_nested_params(v) -- recursive call on other table values
      end
    end

    -- normalize sub-keys with dot notation
    local keys = stringy.split(k, ".")
    if #keys > 1 then -- we have a key containing a dot
      attach_dotted_key(keys, new_obj, parse_value(v))
    else
      new_obj[k] = parse_value(v) -- nothing special with that key, simply attaching the value
    end
  end

  return new_obj
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
      return responses.send_HTTP_BAD_REQUEST(err.tbl)
    end
  end
end

local function parse_params(fn)
  return app_helpers.json_params(function(self, ...)
    local content_type = self.req.headers["content-type"]
    if content_type and string.find(content_type:lower(), "application/json", nil, true) then
      if not self.json then
        return responses.send_HTTP_BAD_REQUEST("Cannot parse JSON body")
      end
    end
    self.params = normalize_nested_params(self.params)
    return fn(self, ...)
  end)
end

app.parse_params = parse_params

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
