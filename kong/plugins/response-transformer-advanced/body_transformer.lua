local transform_utils = require "kong.plugins.response-transformer-advanced.transform_utils"

local cjson_decode = require("cjson").decode
local cjson_encode = require("cjson").encode

local skip_transform = transform_utils.skip_transform
local table_insert = table.insert
local pcall = pcall
local find = string.find
local sub = string.sub
local gsub = string.gsub
local match = string.match
local lower = string.lower
local type = type

local _M = {}

local function read_json_body(body)
  if body then
    local status, res = pcall(cjson_decode, body)
    if status then
      return res
    end
  end
end

local function append_value(current_value, value)
  local current_value_type = type(current_value)

  if current_value_type  == "string" then
    return {current_value, value}
  elseif current_value_type  == "table" then
    table_insert(current_value, value)
    return current_value
  else
    return {value}
  end
end

local function iter(config_array)
  return function(config_array, i, previous_name, previous_value)
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

function _M.is_json_body(content_type)
  return content_type and find(lower(content_type), "application/json", nil, true)
end

-- if resp_code is in allowed response codes (conf.replace.if_status),
-- return string specified in conf.replace.body; otherwise, return nil
function _M.replace_body(conf, resp_body, resp_code)
  local allowed_codes = conf.replace.if_status
  if not skip_transform(resp_code, allowed_codes) and conf.replace.body then
    return conf.replace.body
  end
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
    for _, name, value in iter(conf.replace.json) do
      local v = cjson_encode(value)
      if sub(v, 1, 1) == [["]] and sub(v, -1, -1) == [["]] then
        v = gsub(sub(v, 2, -2), [[\"]], [["]]) -- To prevent having double encoded quotes
      end
      v = gsub(v, [[\/]], [[/]]) -- To prevent having double encoded slashes
      if json_body[name] then
        json_body[name] = v
      end
    end
  end

  -- add new key:value to body
  if not skip_transform(resp_code, conf.add.if_status) then
    for _, name, value in iter(conf.add.json) do
      local v = cjson_encode(value)
      if sub(v, 1, 1) == [["]] and sub(v, -1, -1) == [["]] then
        v = gsub(sub(v, 2, -2), [[\"]], [["]]) -- To prevent having double encoded quotes
      end
      v = gsub(v, [[\/]], [[/]]) -- To prevent having double encoded slashes
      if not json_body[name] then
        json_body[name] = v
      end
    end
  end

  -- append new key:value or value to existing key
  if not skip_transform(resp_code, conf.append.if_status) then
    for _, name, value in iter(conf.append.json) do
      local v = cjson_encode(value)
      if sub(v, 1, 1) == [["]] and sub(v, -1, -1) == [["]] then
        v = gsub(sub(v, 2, -2), [[\"]], [["]]) -- To prevent having double encoded quotes
      end
      v = gsub(v, [[\/]], [[/]]) -- To prevent having double encoded slashes
      json_body[name] = append_value(json_body[name],v)
    end
  end

  return cjson_encode(json_body)
end

return _M
