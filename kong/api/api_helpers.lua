local pl_string = require "pl.stringx"
local utils = require "kong.tools.utils"
local url = require "socket.url"
local app_helpers = require "lapis.application"
local tablex      = require "pl.tablex"
local responses   = require "kong.tools.responses"

local type = type
local pairs = pairs
local remove = table.remove
local tonumber = tonumber
local sub      = string.sub
local find     = string.find

local _M = {}

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
function _M.normalize_nested_params(obj)
  local new_obj = {}

  local function attach_dotted_key(keys, attach_to, value)
    local current_key = keys[1]

    if #keys > 1 then
      if not attach_to[current_key] then
        attach_to[current_key] = {}
      end
      remove(keys, 1)
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
        for _, arr_v in pairs(v) do arr[#arr+1] = arr_v end
        v = arr
      else
        v = _M.normalize_nested_params(v) -- recursive call on other table values
      end
    end

    -- normalize sub-keys with dot notation
    if type(k) == "string" then
      local keys = pl_string.split(k, ".")
      if #keys > 1 then -- we have a key containing a dot
        attach_dotted_key(keys, new_obj, parse_value(v))

      else
        new_obj[k] = parse_value(v) -- nothing special with that key, simply attaching the value
      end

    else
      new_obj[k] = parse_value(v) -- nothing special with that key, simply attaching the value
    end
  end

  return new_obj
end


function _M.resolve_url_params(self)
  local sugar_url = self.args.post.url

  self.args.post.url = nil

  if type(sugar_url) ~= "string" then
    return
  end

  local parsed_url = url.parse(sugar_url)
  if not parsed_url then
    return
  end

  self.args.post.protocol = parsed_url.scheme
  self.args.post.host     = parsed_url.host
  self.args.post.port     = tonumber(parsed_url.port) or
                            parsed_url.port or
                            (parsed_url.scheme == "http" and 80) or
                            (parsed_url.scheme == "https" and 443) or
                            nil
  self.args.post.path     = parsed_url.path
end


function _M.NEEDS_BODY(method)
  return tablex.readonly({ PUT = 1, POST = 2, PATCH = 3 })[method]
end


function _M.parse_params(fn)
  return app_helpers.json_params(function(self, ...)
    if _M.NEEDS_BODY(ngx.req.get_method()) then
      local content_type = self.req.headers["content-type"]
      if content_type then
        content_type = content_type:lower()

        if find(content_type, "application/json", 1, true) and not self.json then
          return responses.send_HTTP_BAD_REQUEST("Cannot parse JSON body")

        elseif find(content_type, "application/x-www-form-urlencode", 1, true) then
          self.params = utils.decode_args(self.params)
        end
      end
    end

    self.params = _M.normalize_nested_params(self.params)

    return fn(self, ...)
  end)
end

function _M.filter_body_content_type(self)
  if not _M.NEEDS_BODY(ngx.req.get_method()) then
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

  return responses.send_HTTP_UNSUPPORTED_MEDIA_TYPE()
end


return _M
