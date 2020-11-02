-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local transform_utils = require "kong.plugins.response-transformer-advanced.transform_utils"

local cjson = require("cjson.safe").new()
local inspect = require("inspect")

local skip_transform = transform_utils.skip_transform
local insert = table.insert
local pcall = pcall
local find = string.find
local sub = string.sub
local gsub = string.gsub
local match = string.match
local lower = string.lower


cjson.decode_array_with_array_mt(true)


local noop = function() end


local _M = {}


local function toboolean(value)
  if value == "true" then
    return true
  else
    return false
  end
end


local function cast_value(value, value_type)
  if value_type == "number" then
    return tonumber(value)
  elseif value_type == "boolean" then
    return toboolean(value)
  else
    return value
  end
end


local function read_json_body(body)
  if body then
    return cjson.decode(body)
  end
end


local function append_value(current_value, value)
  local current_value_type = type(current_value)

  if current_value_type == "string" then
    return { current_value, value }
  end

  if current_value_type == "table" then
    insert(current_value, value)
    return current_value
  end

  return { value }
end


local function iter(config_array)
  if type(config_array) ~= "table" then
    return noop
  end

  return function(config_array, i)
    i = i + 1

    local current_pair = config_array[i]
    if current_pair == nil then -- n + 1
      return nil
    end

    local current_name, current_value = match(current_pair, "^([^:]+):*(.-)$")
    if current_value == "" then
      current_value = nil
    end

    return i, current_name, current_value
  end, config_array, 0
end


local transform_function_cache = setmetatable({}, { __mode = "k" })
local function get_transform_functions(config)
  local route = kong and kong.router and kong.router.get_route() and
                kong.router.get_route().id or ""
  local chunk_name = "route:" .. route .. ":f#"

  local functions = transform_function_cache[config]

  -- transform functions have the following available to them
  local helper_ctx = {
    type = type,
    print = print,
    tostring = tostring,
    inspect = inspect,
    pairs = pairs,
    ipairs = ipairs,
  }

  if not functions then
    -- first call, go compile the functions
    functions = {}
    for i, fn_str in ipairs(config.transform.functions) do
      -- Set function context
      local fn_ctx = {}
      setmetatable(fn_ctx, { __index = helper_ctx })
      local fn = load(fn_str, chunk_name .. i, "t", fn_ctx)     -- load
      local _, actual_fn = pcall(fn)
      insert(functions, actual_fn)
    end

    transform_function_cache[config] = functions
  end

  return ipairs(functions)
end

local function transform_data(data, transform_function)
  local ok, err_or_data = pcall(transform_function, data)
  if not ok then
    return nil, err_or_data
  end

  return err_or_data, nil
end


function _M.is_json_body(content_type)
  return content_type and find(lower(content_type), "application/json", nil, true)
end


-- if resp_code is in allowed response codes (conf.replace.if_status),
-- return string specified in conf.replace.body; otherwise, return resp_body
function _M.replace_body(conf, resp_body, resp_code)
  local allowed_codes = conf.replace.if_status
  if not skip_transform(resp_code, allowed_codes) and conf.replace.body then
    return conf.replace.body
  end
  return resp_body
end


function _M.transform_json_body(conf, buffered_data, resp_code)
  local json_body = read_json_body(buffered_data)
  if json_body == nil then
    return
  end

  -- remove key:value to body
  if not skip_transform(resp_code, conf.remove.if_status) then
    for _, name in iter(conf.remove.json) do
      json_body[name] = nil
    end
  end

  -- replace key:value to body
  if not skip_transform(resp_code, conf.replace.if_status) then
    for i, name, value in iter(conf.replace.json) do
      local v = cjson.encode(value)
      if v and sub(v, 1, 1) == [["]] and sub(v, -1, -1) == [["]] then
        v = gsub(sub(v, 2, -2), [[\"]], [["]]) -- To prevent having double encoded quotes
      end

      v = v and gsub(v, [[\/]], [[/]]) -- To prevent having double encoded slashes

      if conf.replace.json_types then
        local v_type = conf.replace.json_types[i]
        v = cast_value(v, v_type)
      end

      if json_body[name] and v ~= nil then
        json_body[name] = v
      end
    end
  end

  -- add new key:value to body
  if not skip_transform(resp_code, conf.add.if_status) then
    for i, name, value in iter(conf.add.json) do
      local v = cjson.encode(value)
      if v and sub(v, 1, 1) == [["]] and sub(v, -1, -1) == [["]] then
        v = gsub(sub(v, 2, -2), [[\"]], [["]]) -- To prevent having double encoded quotes
      end

      v = v and gsub(v, [[\/]], [[/]]) -- To prevent having double encoded slashes

      if conf.add.json_types then
        local v_type = conf.add.json_types[i]
        v = cast_value(v, v_type)
      end

      if not json_body[name] and v ~= nil then
        json_body[name] = v
      end
    end
  end

  -- append new key:value or value to existing key
  if not skip_transform(resp_code, conf.append.if_status) then
    for i, name, value in iter(conf.append.json) do
      local v = cjson.encode(value)
      if v and sub(v, 1, 1) == [["]] and sub(v, -1, -1) == [["]] then
        v = gsub(sub(v, 2, -2), [[\"]], [["]]) -- To prevent having double encoded quotes
      end

      v = v and gsub(v, [[\/]], [[/]]) -- To prevent having double encoded slashes

      if conf.append.json_types then
        local v_type = conf.append.json_types[i]
        v = cast_value(v, v_type)
      end

      if v ~= nil then
        json_body[name] = append_value(json_body[name],v)
      end
    end
  end

  -- filter body
  if conf.allow.json and not skip_transform(resp_code, conf.remove.if_status) then
    local filtered_json_body = {}
    local filtered = false
    for _, name in iter(conf.allow.json) do
      filtered_json_body[name] = json_body[name]
      filtered = true
    end

    if filtered then
      json_body = filtered_json_body
    end
  end

  local err, data
  -- perform arbitrary transformations on a json
  if not skip_transform(resp_code, conf.transform.if_status) then
    for _, fn in get_transform_functions(conf) do
      data, err = transform_data(json_body, fn)
      if err then
        break
      end
      json_body = data
    end
  end

  return cjson.encode(json_body), err
end

return _M
