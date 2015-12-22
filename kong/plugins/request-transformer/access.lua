local stringy = require "stringy"
local multipart = require "multipart"

local table_insert = table.insert
local req_set_uri_args = ngx.req.set_uri_args
local req_get_uri_args = ngx.req.get_uri_args
local req_set_header = ngx.req.set_header
local req_get_headers = ngx.req.get_headers
local req_read_body = ngx.req.read_body
local req_set_body_data = ngx.req.set_body_data
local req_get_body_data = ngx.req.get_body_data
local req_clear_header = ngx.req.clear_header
local req_get_post_args = ngx.req.get_post_args
local encode_args = ngx.encode_args
local type = type
local string_len = string.len

local unpack = unpack

local _M = {}

local CONTENT_LENGTH = "content-length"
local FORM_URLENCODED = "application/x-www-form-urlencoded"
local MULTIPART_DATA = "multipart/form-data"
local CONTENT_TYPE = "content-type"
local HOST = "host"


local function iter(config_array)
  return function(config_array, i, previous_name, previous_value)
    i = i + 1
    local current_pair = config_array[i]
    if current_pair == nil then -- n + 1
      return nil
    end
    local current_name, current_value = unpack(stringy.split(current_pair, ":"))
    return i, current_name, current_value
  end, config_array, 0
end

local function get_content_type()
  local header_value = req_get_headers()[CONTENT_TYPE]
  if header_value then
    return stringy.strip(header_value):lower()
  end
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

  -- Replace header(s)
  for _, name, value in iter(conf.replace.headers) do
    if req_get_headers()[name] then
      req_set_header(name, value)
      if name:lower() == HOST then -- Host header has a special treatment
        ngx.var.backend_host = value
      end
    end
  end

  -- Add header(s)
  for _, name, value in iter(conf.add.headers) do
    if not req_get_headers()[name] then
      req_set_header(name, value)
      if name:lower() == HOST then -- Host header has a special treatment
        ngx.var.backend_host = value
      end
    end
  end

  -- Append header(s)
  for _, name, value in iter(conf.append.headers) do
    req_set_header(name, append_value(req_get_headers()[name], value))
    if name:lower() == HOST then -- Host header has a special treatment
      ngx.var.backend_host = value
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

local function transform_form_params(conf)
  -- Remove form parameter(s)
  if conf.remove.form  then
    local content_type = get_content_type()
    if content_type and stringy.startswith(content_type, FORM_URLENCODED) then
      req_read_body()
      local parameters = req_get_post_args()

      for _, name, value in iter(conf.remove.form) do
        parameters[name] = nil
      end

      local encoded_args = encode_args(parameters)
      req_set_header(CONTENT_LENGTH, string_len(encoded_args))
      req_set_body_data(encoded_args)
    elseif content_type and stringy.startswith(content_type, MULTIPART_DATA) then
      -- Call req_read_body to read the request body first
      req_read_body()

      local body = req_get_body_data()
      local parameters = multipart(body and body or "", content_type)
      for _, name, value in iter(conf.remove.form) do
        parameters:delete(name)
      end
      local new_data = parameters:tostring()
      req_set_header(CONTENT_LENGTH, string_len(new_data))
      req_set_body_data(new_data)
    end
  end

  -- Replace form parameter(s)
  if conf.replace.form then
    local content_type = get_content_type()
    if content_type and stringy.startswith(content_type, FORM_URLENCODED) then
      -- Call req_read_body to read the request body first
      req_read_body()

      local parameters = req_get_post_args()
      for _, name, value in iter(conf.replace.form) do
        if parameters[name] then
          parameters[name] = value
        end
      end
      local encoded_args = encode_args(parameters)
      req_set_header(CONTENT_LENGTH, string_len(encoded_args))
      req_set_body_data(encoded_args)
    elseif content_type and stringy.startswith(content_type, MULTIPART_DATA) then
      -- Call req_read_body to read the request body first
      req_read_body()

      local body = req_get_body_data()
      local parameters = multipart(body and body or "", content_type)
      for _, name, value in iter(conf.replace.form) do
        if parameters:get(name) then
          parameters:delete(name)
          parameters:set_simple(name, value)
        end
      end
      local new_data = parameters:tostring()
      req_set_header(CONTENT_LENGTH, string_len(new_data))
      req_set_body_data(new_data)
    end
  end

  -- Add form parameter(s)
  if conf.add.form then
    local content_type = get_content_type()
    if content_type and stringy.startswith(content_type, FORM_URLENCODED) then
      -- Call req_read_body to read the request body first
      req_read_body()

      local parameters = req_get_post_args()
      for _, name, value in iter(conf.add.form) do
        if not parameters[name] then
          parameters[name] = value
        end
      end
      local encoded_args = encode_args(parameters)
      req_set_header(CONTENT_LENGTH, string_len(encoded_args))
      req_set_body_data(encoded_args)
    elseif content_type and stringy.startswith(content_type, MULTIPART_DATA) then
      -- Call req_read_body to read the request body first
      req_read_body()

      local body = req_get_body_data()
      local parameters = multipart(body and body or "", content_type)
      for _, name, value in iter(conf.add.form) do
        if not parameters:get(name) then
          parameters:set_simple(name, value)
        end
      end
      local new_data = parameters:tostring()
      req_set_header(CONTENT_LENGTH, string_len(new_data))
      req_set_body_data(new_data)
    end
  end
end

function _M.execute(conf)
  transform_form_params(conf)
  transform_headers(conf)
  transform_querystrings(conf)
end

return _M
