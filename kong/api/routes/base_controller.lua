local utils = require "kong.tools.utils"
local Object = require "classic"
local stringy = require "stringy"
local responses = require "kong.tools.responses"
local json_params = require("lapis.application").json_params

local BaseController = Object:extend()

local APPLICATION_JSON_TYPE = "application/json"
local FORM_URLENCODED_TYPE = "application/x-www-form-urlencoded"

local function check_content_type(req, type)
  return req.headers["content-type"] and string.lower(stringy.strip(req.headers["content-type"])) == type
end

local function render_list_response(req, data, size)
  local next_url

  if data.next_page then
    local url = req.parsed_url.scheme.."://"..req.parsed_url.host..":"..req.parsed_url.port..req.parsed_url.path
    next_url = url.."?"..ngx.encode_args({offset = ngx.encode_base64(data.next_page), size = size})
    data.next_page = nil
  end

  -- This check is required otherwise the response is going to be a
  -- JSON Object and not a JSON array. The reason is because an empty Lua array `{}`
  -- will not be translated as an empty array by cjson, but as an empty object.
  if #data == 0 then
    return "{\"data\":[]}"
  else
    return { data = data, ["next"] = next_url }
  end
end

local function send_dao_error_response(err)
  if err.database then
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(err.message)
  elseif err.unique then
    return responses.send_HTTP_CONFLICT(err.message)
  elseif err.foreign then
    return responses.send_HTTP_NOT_FOUND(err.message)
  elseif err.invalid_type and err.message.id then
    return responses.send_HTTP_NOT_FOUND(err.message)
  else
    return responses.send_HTTP_BAD_REQUEST(err.message)
  end
end

function BaseController.parse_params(schema, params)
  local result = {}
  if schema and params and utils.table_size(params) > 0 then

    local subschemas = {} -- To process later

    for k, v in pairs(schema) do
      if v.type == "table" then
        if v.schema then
          local subschema_params = {}
          for param_key, param_value in pairs(params) do
            if stringy.startswith(param_key, k..".") then
              subschema_params[string.sub(param_key, string.len(k..".") + 1)] = param_value
            end
          end
          subschemas[k] = {
            schema = v.schema,
            params = subschema_params
          }
        elseif params[k] then
          local parts = stringy.split(params[k], ",")
          local sanitized_parts = {}
          for _,v in ipairs(parts) do
            table.insert(sanitized_parts, stringy.strip(v))
          end
          result[k] = sanitized_parts
        end
      elseif v.type == "number" then
        result[k] = tonumber(params[k])
      elseif v.type == "boolean" then
        local str = string.lower(params[k] and params[k] or "")
        if str == "true" then
          result[k] = true
        elseif str == "false" then
          result[k] = false
        else
          result[k] = params[k]
        end
      else
        result[k] = params[k]
      end
    end

    -- Process subschemas
    for k, v in pairs(subschemas) do
      local subschema_value = BaseController.parse_params(type(v.schema) == "table" and v.schema or v.schema(result), v.params)
      if utils.table_size(subschema_value) > 0 then -- Set subschemas to nil if nothing exists
        result[k] = subschema_value
      else
        result[k] = {}
      end
    end
  end

  return result
end

function BaseController:new(dao_collection, collection)
  app:post("/"..collection, function(self)
    if not check_content_type(self.req, FORM_URLENCODED_TYPE) then
      return responses.send_HTTP_UNSUPPORTED_MEDIA_TYPE("Unsupported Content-Type. Use \""..FORM_URLENCODED_TYPE.."\".")
    end

    local params = BaseController.parse_params(dao_collection._schema, self.params)
    local data, err = dao_collection:insert(params)
    if err then
      return send_dao_error_response(err)
    else
      return responses.send_HTTP_CREATED(data)
    end
  end)

  app:get("/"..collection, function(self)
    local size = self.params.size
    if size then
      size = tonumber(size)
    else
      size = 100
    end

    local offset = self.params.offset
    if offset then
      offset = ngx.decode_base64(offset)
    end

    local params = BaseController.parse_params(dao_collection._schema, self.params)
    local data, err = dao_collection:find_by_keys(params, size, offset)
    if err then
      return send_dao_error_response(err)
    end

    local result = render_list_response(self.req, data, size)
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

  app:put("/"..collection.."/:id", json_params(function(self)
    if not check_content_type(self.req, APPLICATION_JSON_TYPE) then
      return responses.send_HTTP_UNSUPPORTED_MEDIA_TYPE("Unsupported Content-Type. Use \""..APPLICATION_JSON_TYPE.."\".")
    end

    local params = self.params
    if self.params.id then
      params.id = self.params.id
    else
      return responses.send_HTTP_NOT_FOUND()
    end

    local data, err = dao_collection:update(params)
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
