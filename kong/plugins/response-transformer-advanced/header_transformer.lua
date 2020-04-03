local transform_utils = require "kong.plugins.response-transformer-advanced.transform_utils"
local pl_stringx = require "pl.stringx"

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

local function regex_match(ngx_header_value, header_value)
  local is_regex = header_value:sub(1, 1) == '/' and header_value:sub(-1) == '/'

  if is_regex then
    header_value = header_value:sub(2, -2)
  end

  local new_ngx_headers = {}

  for k, v in pairs(ngx_header_value) do
    local capture, _, err

    if is_regex then
      capture, _, err = ngx.re.find(v, header_value, "jo")
    else
      capture = v == header_value
    end

    -- Match. Insert the uncaptured header values in a new table
    if not capture and not err then
      table.insert(new_ngx_headers, v)

    -- Bad regex or PCRE error. Do not remove this nginx header value
    elseif err then
      kong.log.err("could not evaluate the regex " .. header_value)
    end

    -- No match. Do not remove this nginx header value
  end

  return new_ngx_headers
end

local function remove_value(ngx_header_value, header_name, header_value)
  if not header_value or not ngx_header_value then
    return nil
  end

  -- Implements the following part of
  -- https://httpwg.org/specs/rfc7230.html#rfc.section.3.2.2
  --
  -- A sender MUST NOT generate multiple header fields with the same field name
  -- in a message unless either the entire field value for that header field is
  -- defined as a comma-separated list [i.e., #(values)] or the header field is
  -- a well-known exception (as noted below).
  if type(ngx_header_value) == "string" then
    local splitted_value = pl_stringx.split(ngx_header_value, ",")

    ngx_header_value = regex_match(splitted_value, header_value)

    if #ngx_header_value == 0 then
      return nil
    end

    return pl_stringx.join(',', ngx_header_value)
  end

  -- Implements the following part of
  -- https://httpwg.org/specs/rfc7230.html#rfc.section.3.2.2

  -- In practice, the "Set-Cookie" header field ([RFC6265]) often appears
  -- multiple times in a response message and does not use the list syntax,
  -- violating the above requirements on multiple header fields with the same
  -- name. Since it cannot be combined into a single field-value, recipients
  -- ought to handle "Set-Cookie" as a special case while processing header
  -- fields.
  if header_name == "Set-Cookie" or type(ngx_header_value) == "table" then
    ngx_header_value = regex_match(ngx_header_value, header_value)

    if #ngx_header_value == 0 then
      return nil
    end

    return ngx_header_value
  end

  return nil
end

local function is_json_body(content_type)
  return content_type and find(lower(content_type), "application/json", nil, true)
end

local function is_body_transform_set(conf)
  return #conf.add.json > 0  or #conf.remove.json > 0 or #conf.replace.json > 0
    or conf.replace.body or #conf.append.json > 0
    or #conf.transform.functions > 0
    or (conf.whitelist.json and #conf.whitelist.json > 0)
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
      ngx_headers[header_name] = remove_value(ngx_headers[header_name],
                                              header_name, header_value)
    end
  end

  -- rename headers
  if conf.rename and not skip_transform(resp_code, conf.rename.if_status) then
      for _, old_header, new_header in iter(conf.rename.headers) do
        if ngx_headers[old_header] ~= nil and new_header then
          ngx_headers[new_header] = ngx_headers[old_header]
          ngx_headers[old_header] = nil
        end
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
