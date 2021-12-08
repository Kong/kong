local multipart = require "multipart"
local cjson = require "cjson"
local pl_template = require "pl.template"
local pl_tablex = require "pl.tablex"

local table_insert = table.insert
local get_uri_args = kong.request.get_query
local set_uri_args = kong.service.request.set_query
local clear_header = kong.service.request.clear_header
local get_header = kong.request.get_header
local set_header = kong.service.request.set_header
local get_headers = kong.request.get_headers
local set_headers = kong.service.request.set_headers
local set_method = kong.service.request.set_method
local set_path = kong.service.request.set_path
local get_raw_body = kong.request.get_raw_body
local set_raw_body = kong.service.request.set_raw_body
local encode_args = ngx.encode_args
local ngx_decode_args = ngx.decode_args
local type = type
local str_find = string.find
local pcall = pcall
local pairs = pairs
local error = error
local rawset = rawset
local pl_copy_table = pl_tablex.deepcopy

local _M = {}
local template_cache = setmetatable( {}, { __mode = "k" })
local template_environment

local DEBUG = ngx.DEBUG
local CONTENT_LENGTH = "content-length"
local CONTENT_TYPE = "content-type"
local HOST = "host"
local JSON, MULTI, ENCODED = "json", "multi_part", "form_encoded"
local EMPTY = pl_tablex.readonly({})


local compile_opts = {
  escape = "\xff", -- disable '#' as a valid template escape
}


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
  if str_find(content_type:lower(), "application/json", nil, true) then
    return JSON
  elseif str_find(content_type:lower(), "multipart/form-data", nil, true) then
    return MULTI
  elseif str_find(content_type:lower(), "application/x-www-form-urlencoded", nil, true) then
    return ENCODED
  end
end

-- meta table for the sandbox, exposing lazily loaded values
local __meta_environment = {
  __index = function(self, key)
    local lazy_loaders = {
      headers = function(self)
        return get_headers() or EMPTY
      end,
      query_params = function(self)
        return get_uri_args() or EMPTY
      end,
      uri_captures = function(self)
        return (ngx.ctx.router_matches or EMPTY).uri_captures or EMPTY
      end,
      shared = function(self)
        return ((kong or EMPTY).ctx or EMPTY).shared or EMPTY
      end,
    }
    local loader = lazy_loaders[key]
    if not loader then
      -- we don't have a loader, so just return nothing
      return
    end
    -- set the result on the table to not load again
    local value = loader()
    rawset(self, key, value)
    return value
  end,
  __newindex = function(self)
    error("This environment is read-only.")
  end,
}

template_environment = setmetatable({
  -- here we can optionally add functions to expose to the sandbox, eg:
  -- tostring = tostring,  -- for example
  -- because headers may contain array elements such as duplicated headers
  -- type is a useful function in these cases. See issue #25.
  type = type,
}, __meta_environment)

local function clear_environment(conf)
  rawset(template_environment, "headers", nil)
  rawset(template_environment, "query_params", nil)
  rawset(template_environment, "uri_captures", nil)
  rawset(template_environment, "shared", nil)
end

local function param_value(source_template, config_array)
  if not source_template or source_template == "" then
    return nil
  end

  -- find compiled templates for this plugin-configuration array
  local compiled_templates = template_cache[config_array]
  if not compiled_templates then
    compiled_templates = {}
    -- store it by `config_array` which is part of the plugin `conf` table
    -- it will be GC'ed at the same time as `conf` and hence invalidate the
    -- compiled templates here as well as the cache-table has weak-keys
    template_cache[config_array] = compiled_templates
  end

  -- Find or compile the specific template
  local compiled_template = compiled_templates[source_template]
  if not compiled_template then
    compiled_template = assert(pl_template.compile(source_template, compile_opts))
    compiled_templates[source_template] = compiled_template
  end

  return compiled_template:render(template_environment)
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
      return i, current_name
    end

    local res, err = param_value(current_value, config_array)
    if err then
      return error("[request-transformer] failed to render the template " ..
                   current_value .. ", error:" .. err)
    end

    kong.log.debug("[request-transformer] template `", current_value,
                   "` rendered to `", res, "`")

    return i, current_name, res
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
  local headers = get_headers()
  local headers_to_remove = {}

  headers.host = nil

  -- Remove header(s)
  for _, name, value in iter(conf.remove.headers) do
    name = name:lower()
    if headers[name] then
      headers[name] = nil
      headers_to_remove[name] = true
    end
  end

  -- Rename headers(s)
  for _, old_name, new_name in iter(conf.rename.headers) do
    old_name = old_name:lower()
    if headers[old_name] then
      local value = headers[old_name]
      headers[new_name] = value
      headers[old_name] = nil
      headers_to_remove[old_name] = true
    end
  end

  -- Replace header(s)
  for _, name, value in iter(conf.replace.headers) do
    name = name:lower()
    if headers[name] or name == HOST then
      headers[name] = value
    end
  end

  -- Add header(s)
  for _, name, value in iter(conf.add.headers) do
    if not headers[name] and name:lower() ~= HOST then
      headers[name] = value
    end
  end

  -- Append header(s)
  for _, name, value in iter(conf.append.headers) do
    local name_lc = name:lower()

    if name_lc ~= HOST and name ~= name_lc and headers[name] ~= nil then
      -- keep original content, use configd case
      -- note: the __index method of table returned by ngx.req.get_header
      -- is overwritten to check for lower case as well, see documentation
      -- for ngx.req.get_header to get more information
      -- effectively, it does this: headers[name] = headers[name] or headers[name_lc]
      headers[name] = headers[name]
      headers[name_lc] = nil
    end

    headers[name] = append_value(headers[name], value)
  end

  for name, _ in pairs(headers_to_remove) do
    clear_header(name)
  end

  set_headers(headers)
end

local function transform_querystrings(conf)

  if not (#conf.remove.querystring > 0 or #conf.rename.querystring > 0 or
          #conf.replace.querystring > 0 or #conf.add.querystring > 0 or
          #conf.append.querystring > 0) then
    return
  end

  local querystring = pl_copy_table(template_environment.query_params)

  -- Remove querystring(s)
  for _, name, value in iter(conf.remove.querystring) do
    querystring[name] = nil
  end

  -- Rename querystring(s)
  for _, old_name, new_name in iter(conf.rename.querystring) do
    local value = querystring[old_name]
    querystring[new_name] = value
    querystring[old_name] = nil
  end

  for _, name, value in iter(conf.replace.querystring) do
    if querystring[name] then
      querystring[name] = value
    end
  end

  -- Add querystring(s)
  for _, name, value in iter(conf.add.querystring) do
    if not querystring[name] then
      querystring[name] = value
    end
  end

  -- Append querystring(s)
  for _, name, value in iter(conf.append.querystring) do
    querystring[name] = append_value(querystring[name], value)
  end
  set_uri_args(querystring)
end

local function transform_json_body(conf, body, content_length)
  local removed, renamed, replaced, added, appended = false, false, false, false, false
  local content_length = (body and #body) or 0
  local parameters = parse_json(body)
  if parameters == nil then
    if content_length > 0 then
      return false, nil
    end
    parameters = {}
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
  local content_type_value = get_header(CONTENT_TYPE)
  local content_type = get_content_type(content_type_value)
  if content_type == nil or #conf.rename.body < 1 and
     #conf.remove.body < 1 and #conf.replace.body < 1 and
     #conf.add.body < 1 and #conf.append.body < 1 then
    return
  end

  -- Call req_read_body to read the request body first
  local body = get_raw_body()
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
    set_raw_body(body)
    set_header(CONTENT_LENGTH, #body)
  end
end

local function transform_method(conf)
  if conf.http_method then
    set_method(conf.http_method:upper())
    if conf.http_method == "GET" or conf.http_method == "HEAD" or conf.http_method == "TRACE" then
      local content_type_value = get_header(CONTENT_TYPE)
      local content_type = get_content_type(content_type_value)
      if content_type == ENCODED then
        -- Also put the body into querystring
        local body = get_raw_body()
        local parameters = decode_args(body)

        -- Append to querystring
        if type(parameters) == "table" and next(parameters) then
          local querystring = get_uri_args()
          for name, value in pairs(parameters) do
            if querystring[name] then
              if type(querystring[name]) == "table" then
                append_value(querystring[name], value)
              else
                querystring[name] = { querystring[name], value }
              end
            else
              querystring[name] = value
            end
          end

          set_uri_args(querystring)
        end
      end
    end
  end
end

local function transform_uri(conf)
  if conf.replace.uri then

    local res, err = param_value(conf.replace.uri, conf.replace)
    if err then
      error("[request-transformer] failed to render the template " ..
        tostring(conf.replace.uri) .. ", error:" .. err)
    end

    kong.log.debug(DEBUG, "[request-transformer] template `", conf.replace.uri,
      "` rendered to `", res, "`")

    if res then
      set_path(res)
    end
  end
end

function _M.execute(conf)
  clear_environment()
  transform_uri(conf)
  transform_method(conf)
  transform_headers(conf)
  transform_body(conf)
  transform_querystrings(conf)
end

return _M
