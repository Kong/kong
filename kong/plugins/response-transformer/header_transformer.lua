local isempty = require "table.isempty"
local mime_type = require "kong.tools.mime_type"
local ngx_re = require "ngx.re"
local pl_stringx = require "pl.stringx"

local kong = kong
local type = type
local match = string.match
local noop = function() end
local ipairs = ipairs
local parse_mime_type = mime_type.parse_mime_type
local mime_type_includes = mime_type.includes
local split = ngx_re.split
local strip = pl_stringx.strip

local JSON_MEDIA_TYPES = {
  { type = "application", subtype = "json" },
  { type = "application", subtype = "*+json" },
}

local _M = {}


local function iter(config_array)
  if type(config_array) ~= "table" then
    return noop
  end

  return function(config_array, i)
    i = i + 1

    local header_to_test = config_array[i]
    if header_to_test == nil then -- n + 1
      return nil
    end

    local header_to_test_name, header_to_test_value = match(header_to_test, "^([^:]+):*(.-)$")
    if header_to_test_value == "" then
      header_to_test_value = nil
    end

    return i, header_to_test_name, header_to_test_value
  end, config_array, 0
end


local function is_json_body(content_type)
  if not content_type then
    return false
  end
  local content_types = split(content_type, ",")
  for _, content_type in ipairs(content_types) do
    local t, subtype = parse_mime_type(strip(content_type))
    if not t or not subtype then
      goto continue
    end
    local media_type = { type = t, subtype = subtype }
    for _, this_type in ipairs(JSON_MEDIA_TYPES) do
      if mime_type_includes(this_type, media_type) then
        return true
      end
    end
    ::continue::
  end

  return false
end


local function is_body_transform_set(conf)
  return not isempty(conf.add.json    ) or
         not isempty(conf.remove.json ) or
         not isempty(conf.replace.json) or
         not isempty(conf.append.json )
end


-- export utility functions
_M.is_json_body = is_json_body
_M.is_body_transform_set = is_body_transform_set


---
--   # Example:
--   ngx.headers = header_filter.transform_headers(conf, ngx.headers)
-- We run transformations in following order: remove, rename, replace, add, append.
-- @param[type=table] conf Plugin configuration.
-- @param[type=table] ngx_headers Table of headers, that should be `ngx.headers`
-- @return table A table containing the new headers.
function _M.transform_headers(conf, headers)
  local clear_header = kong.response.clear_header
  local set_header   = kong.response.set_header
  local add_header   = kong.response.add_header

  -- remove headers
  for _, header_name in iter(conf.remove.headers) do
      clear_header(header_name)
  end

  -- rename headers(s)
  for _, old_name, new_name in iter(conf.rename.headers) do
    if headers[old_name] ~= nil and new_name then
      local value = headers[old_name]
      set_header(new_name, value)
      clear_header(old_name)
    end
  end

  -- replace headers
  for _, header_name, header_value in iter(conf.replace.headers) do
    if headers[header_name] ~= nil and header_value then
      set_header(header_name, header_value)
    end
  end

  -- add headers
  for _, header_name, header_value in iter(conf.add.headers) do
    if headers[header_name] == nil and header_value then
      set_header(header_name, header_value)
    end
  end

  -- append headers
  for _, header_name, header_value in iter(conf.append.headers) do
    add_header(header_name, header_value)
  end

  -- Removing the content-length header because the body is going to change
  if is_body_transform_set(conf) and is_json_body(headers["Content-Type"]) then
    clear_header("Content-Length")
  end
end

return _M
