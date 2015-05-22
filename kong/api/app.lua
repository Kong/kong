local lapis = require "lapis"
local utils = require "kong.tools.utils"
local stringy = require "stringy"
local responses = require "kong.tools.responses"
local app_helpers = require "lapis.application"
local app = lapis.Application()

-- Put nested keys in objects:
-- Normalize dotted keys in objects.
-- Example: {["key.value.sub"]=1234} becomes {key = {value = {sub=1234}}
-- @param `obj` Object to normalize
-- @return `normalized_object`
local function normalize_nested_params(obj)
  local normalized_obj = {} -- create a copy to not modify obj while it is in a loop.

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
      local current_level = keys[1] -- let's create an empty object for the first level
      if normalized_obj[current_level] == nil then
        normalized_obj[current_level] = {}
      end
      table.remove(keys, 1) -- remove the first level
      normalized_obj[k] = nil -- remove it from the object
      if #keys > 0 then -- if we still have some keys, then there are more levels of nestinf
        normalized_obj[current_level][table.concat(keys, ".")] = v
        normalized_obj[current_level] = normalize_nested_params(normalized_obj[current_level])
      else
        normalized_obj[current_level] = v -- latest level of nesting, attaching the value
      end
    else
      normalized_obj[k] = v -- nothing special with that key, simply attaching the value
    end
  end

  return normalized_obj
end

local function default_on_error(self)
  local err = self.errors[1]
  if type(err) == "table" then
    if err.database then
      return responses.send_HTTP_INTERNAL_SERVER_ERROR(err.message)
    elseif err.unique then
      return responses.send_HTTP_CONFLICT(err.message)
    elseif err.foreign then
      return responses.send_HTTP_NOT_FOUND(err.message)
    elseif err.invalid_type and err.message.id then
      return responses.send_HTTP_BAD_REQUEST(err.message)
    else
      return responses.send_HTTP_BAD_REQUEST(err.message)
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
  ngx.log(ngx.ERR, err.."\n"..trace)

  local iterator, iter_err = ngx.re.gmatch(err, ".+:\\d+:\\s*(.+)")
  if iter_err then
    ngx.log(ngx.ERR, iter_err)
  end

  local m, iter_err = iterator()
  if iter_err then
    ngx.log(ngx.ERR, iter_err)
  end

  if m and table.getn(m) > 0 then
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(m[1])
  else
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
  end
end

local handler_helpers = {
  responses = responses,
  yield_error = app_helpers.yield_error
}

local function attach_routes(routes)
  for route_path, methods in pairs(routes) do
    if not methods.on_error then
      methods.on_error = default_on_error
    end

    for k, v in pairs(methods) do
      local method = function(self)
        return v(self, dao, handler_helpers)
      end
      methods[k] = parse_params(method)
    end

    app:match(route_path, route_path, app_helpers.respond_to(methods))
  end
end

for _, v in ipairs({"kong", "apis", "consumers", "plugins_configurations"}) do
  local routes = require("kong.api.routes."..v)
  attach_routes(routes)
end

-- Loading plugins routes
if configuration and configuration.plugins_available then
  for _, v in ipairs(configuration.plugins_available) do
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
