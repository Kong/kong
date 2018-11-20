local transform_utils = require "kong.plugins.response-transformer-advanced.transform_utils"

local skip_transform = transform_utils.skip_transform
local insert = table.insert
local type = type
local find = string.find
local lower = string.lower
local match = string.match

local _M = {}

local function iter(config_array)
  return function(config_array, i, previous_header_name, previous_header_value)
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

local function append_value(current_value, value)
  local current_value_type = type(current_value)

  if current_value_type == "string" then
    return {current_value, value}
  elseif current_value_type == "table" then
    insert(current_value, value)
    return current_value
  else
    return {value}
  end
end

local function is_json_body(content_type)
  return content_type and find(lower(content_type), "application/json", nil, true)
end

local function is_body_transform_set(conf)
  return #conf.add.json > 0  or #conf.remove.json > 0 or #conf.replace.json > 0
    or conf.replace.body or #conf.append.json > 0
end

-- export utility functions
_M.is_json_body = is_json_body
_M.is_body_transform_set = is_body_transform_set

---
--   # Example:
--   ngx.headers = header_filter.transform_headers(conf, ngx.headers)
-- We run transformations in following order: remove, replace, add, append.
-- @param[type=table] conf Plugin configuration.
-- @param[type=table] ngx_headers Table of headers, that should be `ngx.headers`
-- @return table A table containing the new headers.
function _M.transform_headers(conf, ngx_headers, resp_code)
  -- remove headers
  if not skip_transform(resp_code, conf.remove.if_status) then
    for _, header_name, header_value in iter(conf.remove.headers) do
        ngx_headers[header_name] = nil
    end
  end

  -- replace headers
  if not skip_transform(resp_code, conf.replace.if_status) then
    for _, header_name, header_value in iter(conf.replace.headers) do
      if ngx_headers[header_name] ~= nil then
        ngx_headers[header_name] = header_value
      end
    end
  end

  -- add headers
  if not skip_transform(resp_code, conf.add.if_status) then
    for _, header_name, header_value in iter(conf.add.headers) do
      if ngx_headers[header_name] == nil then
        ngx_headers[header_name] = header_value
      end
    end
  end

  -- append headers
  if not skip_transform(resp_code, conf.append.if_status) then
    for _, header_name, header_value in iter(conf.append.headers) do
      ngx_headers[header_name] = append_value(ngx_headers[header_name], header_value)
    end
  end

  -- Removing the content-length header if the body is going to change:
  -- - Body transform is set, it's full body (no matter what content-type) or
  -- - Body transform is set, it's not full body, but is JSON (only content-type
  --   supported for non-full body transforms)
  if is_body_transform_set(conf) and (conf.replace.body or
    is_json_body(ngx_headers["content-type"])) then
    ngx_headers["content-length"] = nil
  end
end

return _M
