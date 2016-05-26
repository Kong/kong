local stringy = require "stringy"
local cjson = require "cjson"

local table_insert = table.insert
local pcall = pcall
local string_find = string.find
local unpack = unpack
local type = type

local _M = {}

local function read_json_body(body)
  if body then
    local status, res = pcall(cjson.decode, body)
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
    local current_name, current_value = unpack(stringy.split(current_pair, ":"))
    return i, current_name, current_value  
  end, config_array, 0
end

function _M.is_json_body(content_type)
  return content_type and string_find(content_type:lower(), "application/json", nil, true)
end

function _M.transform_json_body(conf, buffered_data)
  local json_body = read_json_body(buffered_data)
  if json_body == nil then return end
  
  -- remove key:value to body
  for _, name in iter(conf.remove.json) do
    json_body[name] = nil
  end
  
  -- replace key:value to body
  for _, name, value in iter(conf.replace.json) do
    local v = cjson.encode(value)
    if stringy.startswith(v, "\"") and stringy.endswith(v, "\"") then
      v = v:sub(2, v:len() - 1):gsub("\\\"", "\"") -- To prevent having double encoded quotes
    end
    v = v:gsub("\\/", "/") -- To prevent having double encoded slashes
    if json_body[name] then
      json_body[name] = v
    end
  end
  
  -- add new key:value to body    
  for _, name, value in iter(conf.add.json) do
    local v = cjson.encode(value)
    if stringy.startswith(v, "\"") and stringy.endswith(v, "\"") then
      v = v:sub(2, v:len() - 1):gsub("\\\"", "\"") -- To prevent having double encoded quotes
    end
    v = v:gsub("\\/", "/") -- To prevent having double encoded slashes
    if not json_body[name] then
      json_body[name] = v
    end
  end
  
  -- append new key:value or value to existing key    
  for _, name, value in iter(conf.append.json) do
    local v = cjson.encode(value)
    if stringy.startswith(v, "\"") and stringy.endswith(v, "\"") then
      v = v:sub(2, v:len() - 1):gsub("\\\"", "\"") -- To prevent having double encoded quotes
    end
    v = v:gsub("\\/", "/") -- To prevent having double encoded slashes
    json_body[name] = append_value(json_body[name],v)
  end
  
  return cjson.encode(json_body) 
end

return _M
