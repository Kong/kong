local pl_string = require "pl.stringx"
local utils = require "kong.tools.utils"
local url = require "socket.url"

local type = type
local pairs = pairs
local remove = table.remove
local tonumber = tonumber

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


return _M
