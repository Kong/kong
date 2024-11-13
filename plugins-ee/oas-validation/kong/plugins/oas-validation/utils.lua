-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson = require("cjson.safe").new()

local json_decode = cjson.decode
local gsub = string.gsub
local match = string.match
local lower = string.lower
local pairs = pairs
local re_match = ngx.re.match

cjson.decode_array_with_array_mt(true)

local EMPTY_T = {}
local DEFAULT_BASE_PATHS = { '/' }

local _M = {}

function _M.get_req_body()
  ngx.req.read_body()
  local body_data = ngx.req.get_body_data()

  if not body_data then
    --no raw body, check temp body
    local body_file = ngx.req.get_body_file()
    if body_file then
      local file, err = io.open(body_file, "r")
      if err then
        return nil, err
      end

      body_data = file:read("*all")
      file:close()
    end
  end

  if not body_data or #body_data == 0 then
    return nil
  end

  return body_data
end

function _M.get_req_body_json()
  local body_data = _M.get_req_body()

  -- try to decode body data as json
  local body, err = json_decode(body_data)
  if err then
    return nil, "request body is not valid JSON"
  end

  return body
end

function _M.retrieve_operation(spec, path, method)
  for _, spec_path in pairs(spec.sorted_paths or EMPTY_T) do
    for _, base_path in ipairs(spec.base_paths or DEFAULT_BASE_PATHS) do
      local formatted_path = base_path == '/' and spec_path or (base_path .. spec_path)
      formatted_path = gsub(formatted_path, "[-.+*|]", "%%%1")
      formatted_path = "^" .. gsub(formatted_path, "{(.-)}", "[^/]+") .. "$"
      if match(path, formatted_path) then
        return spec.paths[spec_path], spec_path, spec.paths[spec_path][lower(method)]
      end
    end
  end
end

function _M.traverse(object, property_name, callback)
  if type(object) ~= "table" then
    return
  end

  for key, value in pairs(object) do
    if key == property_name then
      callback(key, value, object)
    end

    if type(value) == "table" then
      _M.traverse(value, property_name, callback)
    end
  end
end


local BOOLEAN_MAP = {
  ["true"] = true,
  ["false"] = false,
}


local function normalize_value(value, typ)
  if typ == "integer" or typ == "number" then
    local v = tonumber(value)
    if v then
      return v
    end
    return nil, "failed to parse '" .. value .. "' from string to " .. typ
  end

  if typ == "boolean" then
    local v = BOOLEAN_MAP[value]
    if v ~= nil then
      return v
    end
    return nil, "failed to parse '" .. value .. "' from string to " .. typ
  end

  return value
end


--- Normalizes a value based on its schema.
-- values lost their orignal type after transporting from querystring and cookie.
-- it's necessary to convert back to its original type from literal(string) value
function _M.normalize(value, schema)
  local value_type = type(value)
  assert(value_type == "table" or value_type == "string")

  if value_type == "string" then
    return normalize_value(value, schema.type)
  end

  if schema.type == "object" then
    for k, v in pairs(value) do
      local key_schema = schema.properties[k]
      local normalized_value, err = _M.normalize(v, key_schema)
      if err then
        return nil, err
      end
      value[k] = normalized_value
    end

  elseif schema.type == "array" then
    local item_schema = schema.items
    for k, v in pairs(value) do
      local normalized_value, err = _M.normalize(v, item_schema)
      if err then
        return nil, err
      end
      value[k] = normalized_value
    end
  end

  return value
end

function _M.is_version_30x(version)
  if not version then
    return false
  end
  local m = re_match(version, [[^3\.0\.\d$]], "jo")
  return m ~= nil
end

function _M.is_version_31x(version)
  if not version then
    return false
  end

  local m = re_match(version, [[^3\.1\.\d$]], "jo")
  return m ~= nil
end



return _M
