local multipart = require "multipart"
local cjson = require "cjson"

local table_insert = table.insert
local req_set_uri_args = ngx.req.set_uri_args
local req_get_uri_args = ngx.req.get_uri_args
local req_set_header = ngx.req.set_header
local req_get_headers = ngx.req.get_headers
local req_read_body = ngx.req.read_body
local req_set_body_data = ngx.req.set_body_data
local req_get_body_data = ngx.req.get_body_data
local req_clear_header = ngx.req.clear_header
local req_set_method = ngx.req.set_method
local encode_args = ngx.encode_args
local ngx_decode_args = ngx.decode_args
local type = type
local string_find = string.find
local pcall = pcall

local _M = {}

local CONTENT_LENGTH = "content-length"
local CONTENT_TYPE = "content-type"
local HOST = "host"
local JSON, MULTI, ENCODED = "json", "multi_part", "form_encoded"

local function parse_json(body)
  if body then
    local status, res = pcall(cjson.decode, body)
    if status then
      return res
    end
  end
end

local function decode_args(body)
  if body then
    return ngx_decode_args(body)
  end
  return {}
end

local function get_content_type(content_type)
  if content_type == nil then
    return
  end
  if string_find(content_type:lower(), "application/json", nil, true) then
    return JSON
  elseif string_find(content_type:lower(), "multipart/form-data", nil, true) then
    return MULTI
  elseif string_find(content_type:lower(), "application/x-www-form-urlencoded", nil, true) then
    return ENCODED
  end
end

local function iter(config_array)
  return function(config_array, i, previous_name, previous_value)
    i = i + 1
    local current_pair = config_array[i]
    if current_pair == nil then -- n + 1
      return nil
    end

    local current_name, current_value = current_pair:match("^([^:]+):*(.-)$")
    if current_value == "" then
      current_value = nil
    end

    return i, current_name, current_value
  end, config_array, 0
end

local function append_value(current_value, value)
  local current_value_type = type(current_value)

  if current_value_type  == "string" then
    return { current_value, value }
  elseif current_value_type  == "table" then
    table_insert(current_value, value)
    return current_value
  else
    return { value }
  end
end

local function transform_headers(conf)
  -- Remove header(s)
  for _, name, value in iter(conf.remove.headers) do
    req_clear_header(name)
  end

  -- Rename headers(s)
  for _, old_name, new_name in iter(conf.rename.headers) do
    if req_get_headers()[old_name] then
      local value = req_get_headers()[old_name]
      req_set_header(new_name, value)
      req_clear_header(old_name)
    end
  end

  -- Replace header(s)
  for _, name, value in iter(conf.replace.headers) do
    if req_get_headers()[name] then
      req_set_header(name, value)
      if name:lower() == HOST then -- Host header has a special treatment
        ngx.var.upstream_host = value
      end
    end
  end

  -- Add header(s)
  for _, name, value in iter(conf.add.headers) do
    if not req_get_headers()[name] then
      req_set_header(name, value)
      if name:lower() == HOST then -- Host header has a special treatment
        ngx.var.upstream_host = value
      end
    end
  end

  -- Append header(s)
  for _, name, value in iter(conf.append.headers) do
    req_set_header(name, append_value(req_get_headers()[name], value))
    if name:lower() == HOST then -- Host header has a special treatment
      ngx.var.upstream_host = value
    end
  end
end

local function transform_querystrings(conf)
  -- Remove querystring(s)
  if conf.remove.querystring then
    local querystring = req_get_uri_args()
    for _, name, value in iter(conf.remove.querystring) do
      querystring[name] = nil
    end
    req_set_uri_args(querystring)
  end

  -- Rename querystring(s)
  if conf.rename.querystring then
    local querystring = req_get_uri_args()
    for _, old_name, new_name in iter(conf.rename.querystring) do
      local value = querystring[old_name]
      querystring[new_name] = value
      querystring[old_name] = nil
    end
    req_set_uri_args(querystring)
  end

  -- Replace querystring(s)
  if conf.replace.querystring then
    local querystring = req_get_uri_args()
    for _, name, value in iter(conf.replace.querystring) do
      if querystring[name] then
        querystring[name] = value
      end
    end
    req_set_uri_args(querystring)
  end

  -- Add querystring(s)
  if conf.add.querystring then
    local querystring = req_get_uri_args()
    for _, name, value in iter(conf.add.querystring) do
      if not querystring[name] then
        querystring[name] = value
      end
    end
    req_set_uri_args(querystring)
  end

  -- Append querystring(s)
  if conf.append.querystring then
    local querystring = req_get_uri_args()
    for _, name, value in iter(conf.append.querystring) do
      querystring[name] = append_value(querystring[name], value)
    end
    req_set_uri_args(querystring)
  end
end

local function transform_json_body(conf, body, content_length)
  local removed, renamed, replaced, added, appended = false, false, false, false, false
  local content_length = (body and #body) or 0
  local parameters = parse_json(body)
  if parameters == nil and content_length > 0 then
    return false, nil
  end

  if content_length > 0 and #conf.remove.body > 0 then
    for _, name, value in iter(conf.remove.body) do
      parameters[name] = nil
      removed = true
    end
  end

  if content_length > 0 and #conf.rename.body > 0 then
    for _, old_name, new_name in iter(conf.rename.body) do
      local value = parameters[old_name]
      parameters[new_name] = value
      parameters[old_name] = nil
      renamed = true
    end
  end

  if content_length > 0 and #conf.replace.body > 0 then
    for _, name, value in iter(conf.replace.body) do
      if parameters[name] then
        parameters[name] = value
        replaced = true
      end
    end
  end

  if #conf.add.body > 0 then
    for _, name, value in iter(conf.add.body) do
      if not parameters[name] then
        parameters[name] = value
        added = true
      end
    end
  end

  if #conf.append.body > 0 then
    for _, name, value in iter(conf.append.body) do
      local old_value = parameters[name]
      parameters[name] = append_value(old_value, value)
      appended = true
    end
  end

  if removed or renamed or replaced or added or appended then
    return true, cjson.encode(parameters)
  end
end

local function transform_url_encoded_body(conf, body, content_length)
  local renamed, removed, replaced, added, appended = false, false, false, false, false
  local parameters = decode_args(body)

  if content_length > 0 and #conf.remove.body > 0 then
    for _, name, value in iter(conf.remove.body) do
      parameters[name] = nil
      removed = true
    end
  end

  if content_length > 0 and #conf.rename.body > 0 then
    for _, old_name, new_name in iter(conf.rename.body) do
      local value = parameters[old_name]
      parameters[new_name] = value
      parameters[old_name] = nil
      renamed = true
    end
  end

  if content_length > 0 and #conf.replace.body > 0 then
    for _, name, value in iter(conf.replace.body) do
      if parameters[name] then
        parameters[name] = value
        replaced = true
      end
    end
  end

  if #conf.add.body > 0 then
    for _, name, value in iter(conf.add.body) do
      if parameters[name] == nil then
        parameters[name] = value
        added = true
      end
    end
  end

  if #conf.append.body > 0 then
    for _, name, value in iter(conf.append.body) do
      local old_value = parameters[name]
      parameters[name] = append_value(old_value, value)
      appended = true
    end
  end

  if removed or renamed or replaced or added or appended then
    return true, encode_args(parameters)
  end
end

local function transform_multipart_body(conf, body, content_length, content_type_value)
  local removed, renamed, replaced, added, appended = false, false, false, false, false
  local parameters = multipart(body and body or "", content_type_value)

  if content_length > 0 and #conf.rename.body > 0 then
    for _, old_name, new_name in iter(conf.rename.body) do
      if parameters:get(old_name) then
        local value = parameters:get(old_name).value
        parameters:set_simple(new_name, value)
        parameters:delete(old_name)
        renamed = true
      end
    end
  end

  if content_length > 0 and #conf.remove.body > 0 then
    for _, name, value in iter(conf.remove.body) do
      parameters:delete(name)
      removed = true
    end
  end

  if content_length > 0 and #conf.replace.body > 0 then
    for _, name, value in iter(conf.replace.body) do
      if parameters:get(name) then
        parameters:delete(name)
        parameters:set_simple(name, value)
        replaced = true
      end
    end
  end

  if #conf.add.body > 0 then
    for _, name, value in iter(conf.add.body) do
      if not parameters:get(name) then
        parameters:set_simple(name, value)
        added = true
      end
    end
  end

  if removed or renamed or replaced or added or appended then
    return true, parameters:tostring()
  end
end

local function transform_body(conf)
  local content_type_value = req_get_headers()[CONTENT_TYPE]
  local content_type = get_content_type(content_type_value)
  if content_type == nil or #conf.rename.body < 1 and
     #conf.remove.body < 1 and #conf.replace.body < 1 and
     #conf.add.body < 1 and #conf.append.body < 1 then
    return
  end

  -- Call req_read_body to read the request body first
  req_read_body()
  local body = req_get_body_data()
  local is_body_transformed = false
  local content_length = (body and #body) or 0

  if content_type == ENCODED then
    is_body_transformed, body = transform_url_encoded_body(conf, body, content_length)
  elseif content_type == MULTI then
    is_body_transformed, body = transform_multipart_body(conf, body, content_length, content_type_value)
  elseif content_type == JSON then
    is_body_transformed, body = transform_json_body(conf, body, content_length)
  end

  if is_body_transformed then
    req_set_body_data(body)
    req_set_header(CONTENT_LENGTH, #body)
  end
end

local function transform_method(conf)
  if conf.http_method then
    req_set_method(ngx["HTTP_" .. conf.http_method:upper()])
    if conf.http_method == "GET" or conf.http_method == "HEAD" or conf.http_method == "TRACE" then
      local content_type_value = req_get_headers()[CONTENT_TYPE]
      local content_type = get_content_type(content_type_value)
      if content_type == ENCODED then
        -- Also put the body into querystring

        -- Read the body
        req_read_body()
        local body = req_get_body_data()
        local parameters = decode_args(body)

        -- Append to querystring
        local querystring = req_get_uri_args()
        for name, value in pairs(parameters) do
          querystring[name] = value
        end
        req_set_uri_args(querystring)
      end
    end
  end
end

function _M.execute(conf)
  transform_method(conf)
  transform_body(conf)
  transform_headers(conf)
  transform_querystrings(conf)
end

return _M
