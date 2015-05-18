local json = require "cjson"
local utils = require "kong.tools.utils"
local Object = require "classic"
local stringy = require "stringy"
local responses = require "kong.tools.responses"
local json_params = require("lapis.application").json_params

local BaseController = Object:extend()

local function send_dao_error_response(err)
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

local function parse_params(fn)
  return json_params(function(self, ...)
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

-- Expose for children classes and unit testing
BaseController.parse_params = parse_params

function BaseController:new(dao_collection, collection)
  app:post("/"..collection, parse_params(function(self)
    local data, err = dao_collection:insert(self.params)
    if err then
      return send_dao_error_response(err)
    else
      return responses.send_HTTP_CREATED(data)
    end
  end))

  app:put("/"..collection, parse_params(function(self)
    local data, err
    if self.params.id then
      data, err = dao_collection:update(self.params)
      if not err then
        return responses.send_HTTP_OK(data)
      end
    else
      data, err = dao_collection:insert(self.params)
      if not err then
        return responses.send_HTTP_CREATED(data)
      end
    end

    if err then
      return send_dao_error_response(err)
    end
  end))

  app:get("/"..collection, function(self)
    local size = self.params.size and tonumber(self.params.size) or 100
    local offset = self.params.offset and ngx.decode_base64(self.params.offset) or nil

    self.params.size = nil
    self.params.offset = nil

    local data, err = dao_collection:find_by_keys(self.params, size, offset)
    if err then
      return send_dao_error_response(err)
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
  end)

  app:get("/"..collection.."/:id", function(self)
    local data, err = dao_collection:find_one(self.params.id)
    if err then
      return send_dao_error_response(err)
    end
    if data then
      return responses.send_HTTP_OK(data)
    else
      return responses.send_HTTP_NOT_FOUND()
    end
  end)

  app:delete("/"..collection.."/:id", function(self)
    local ok, err = dao_collection:delete(self.params.id)
    if not ok then
      if err then
        return send_dao_error_response(err)
      else
        return responses.send_HTTP_NOT_FOUND()
      end
    else
      return responses.send_HTTP_NO_CONTENT()
    end
  end)

  app:patch("/"..collection.."/:id", parse_params(function(self)
    local data, err = dao_collection:update(self.params)
    if err then
      return send_dao_error_response(err)
    elseif not data then
      return responses.send_HTTP_NOT_FOUND()
    else
      return responses.send_HTTP_OK(data)
    end
  end))
end

return BaseController
