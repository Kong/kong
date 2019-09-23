local kong = kong
local type = type
local find = string.find
local lower = string.lower
local match = string.match
local noop = function() end


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
  return content_type and find(lower(content_type), "application/json", nil, true)
end


local function is_body_transform_set(conf)
  return #conf.add.json     > 0 or
         #conf.remove.json  > 0 or
         #conf.replace.json > 0 or
         #conf.append.json  > 0
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
  -- remove headers
  for _, header_name in iter(conf.remove.headers) do
      kong.response.clear_header(header_name)
  end

  -- rename headers(s)
  for _, old_name, new_name in iter(conf.rename.headers) do
    if headers[old_name] ~= nil and new_name then
      local value = headers[old_name]
      kong.response.set_header(new_name, value)
      kong.response.clear_header(old_name)
    end
  end

  -- replace headers
  for _, header_name, header_value in iter(conf.replace.headers) do
    if headers[header_name] ~= nil and header_value then
      kong.response.set_header(header_name, header_value)
    end
  end

  -- add headers
  for _, header_name, header_value in iter(conf.add.headers) do
    if headers[header_name] == nil and header_value then
      kong.response.set_header(header_name, header_value)
    end
  end

  -- append headers
  for _, header_name, header_value in iter(conf.append.headers) do
    kong.response.add_header(header_name, header_value)
  end

  -- Removing the content-length header because the body is going to change
  if is_body_transform_set(conf) and is_json_body(headers["Content-Type"]) then
    kong.response.clear_header("Content-Length")
  end
end

return _M
