local Object = require "kong.vendor.classic"
local utils = require "kong.tools.utils"
local stringy = require "stringy"
local responses = require "kong.tools.responses"
local app_helpers = require "lapis.application"

local function return_paginated_set(self, dao_collection)
  local size = self.params.size and tonumber(self.params.size) or 100
  local offset = self.params.offset and ngx.decode_base64(self.params.offset) or nil

  self.params.size = nil
  self.params.offset = nil

  local data, err = dao_collection:find_by_keys(self.params, size, offset)
  if err then
    return app_helpers.yield_error(err)
  end

  local next_url
  if data.next_page then
    next_url = self:build_url(self.req.parsed_url.path, {
      port = self.req.parsed_url.port,
      query = ngx.encode_args({
                offset = ngx.encode_base64(data.next_page),
                size = size
              })
    })
    data.next_page = nil
  end

  -- This check is required otherwise the response is going to be a
  -- JSON Object and not a JSON array. The reason is because an empty Lua array `{}`
  -- will not be translated as an empty array by cjson, but as an empty object.
  local result = #data == 0 and "{\"data\":[]}" or {data=data, ["next"]=next_url}

  return responses.send_HTTP_OK(result, type(result) ~= "table")
end

local _M = Object:extend()

function _M:new(app, dao_factory)
  self.app = app
  self.dao_factory = dao_factory
  self.helpers = {
    return_paginated_set = return_paginated_set,
    responses = responses,
    yield_error = app_helpers.yield_error
  }
end

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
        normalized_obj[current_level][table.concat(keys, ".")] = parse_value(v)
        normalized_obj[current_level] = normalize_nested_params(normalized_obj[current_level])
      else
        normalized_obj[current_level] = parse_value(v) -- latest level of nesting, attaching the value
      end
    else
      normalized_obj[k] = parse_value(v) -- nothing special with that key, simply attaching the value
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

function _M.parse_params(fn)
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

function _M:attach(routes)
  for route_path, methods in pairs(routes) do
    if not methods.on_error then
      methods.on_error = default_on_error
    end

    for k, v in pairs(methods) do
      local dao_factory = self.dao_factory
      local helpers = self.helpers
      local method = function(self)
        return v(self, dao_factory, helpers)
      end
      methods[k] = _M.parse_params(method)
    end

    self.app:match(route_path, route_path, app_helpers.respond_to(methods))
  end
end

return _M
