-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local transform_utils = require "kong.plugins.response-transformer-advanced.transform_utils"
local json_navigator = require "kong.enterprise_edition.transformations.plugins.json_navigator"
local sandbox = require "kong.tools.sandbox"
local mime_type = require "kong.tools.mime_type"
local ngx_re = require "ngx.re"
local pl_stringx = require "pl.stringx"
local cjson = require("cjson.safe").new()
local tablex = require("pl.tablex")

local skip_transform = transform_utils.skip_transform
local navigate_and_apply = json_navigator.navigate_and_apply
local insert = table.insert
local sub = string.sub
local gsub = string.gsub
local match = string.match
local ipairs = ipairs
local parse_mime_type = mime_type.parse_mime_type
local mime_type_includes = mime_type.includes
local split = ngx_re.split
local strip = pl_stringx.strip


local next = next
local pcall = pcall

local EMPTY_ARRAY = tablex.readonly({})


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

  local opts = { chunk_name = chunk_name }

  local functions = transform_function_cache[config]

  if not functions then

    functions = {}

    for i, fn_str in ipairs(config.transform.functions) do
      insert(functions, assert(sandbox.validate_function(fn_str, opts)))
    end

    transform_function_cache[config] = functions
  end

  return functions
end


function _M.is_json_body(content_type)
  if not content_type then
    return false
  end
  local content_types = split(content_type, ",")
  local expected_media_type = { type = "application", subtype = "json" }
  for _, content_type in ipairs(content_types) do
    local t, subtype = parse_mime_type(strip(content_type))
    if not t or not subtype then
      goto continue
    end
    local media_type = { type = t, subtype = subtype }
    if mime_type_includes(expected_media_type, media_type) then
      return true
    end
    ::continue::
  end

  return false
end


local function arbitrary_transform(conf, data, fn)
  local opts = { dots_in_keys = conf.dots_in_keys }
  if next(conf.transform.json) == nil then
    return fn(data)
  end

  for _, path, value in iter(conf.transform.json) do
     -- wrapper with implicit value for navigate_and_apply
     local wrap_fn = function(data, key)
       return fn(data, key, value)
     end

     navigate_and_apply(data, path, wrap_fn, opts)
  end

  return data
end

local function init_json_path(json, paths)
  if type(json) == "table" then
    for _, path in ipairs(paths or EMPTY_ARRAY) do
      if json[path] == nil then
        json[path] = {}
      end
      json = json[path]
    end
  end

  return json
end

function _M.determine_transform_operations(conf, resp_code, transform_ops)
  if conf.remove and conf.remove.json and #conf.remove.json > 0
     and not skip_transform(resp_code, conf.remove.if_status) then
    transform_ops.remove_body = true
    transform_ops._need_transform = true
  end

  if conf.replace and conf.replace.json and #conf.replace.json > 0
     and not skip_transform(resp_code, conf.replace.if_status) then
    transform_ops.replace_body = true
    transform_ops._need_transform = true
  end

  if conf.add and conf.add.json and #conf.add.json > 0
     and not skip_transform(resp_code, conf.add.if_status) then
    transform_ops.add_body = true
    transform_ops._need_transform = true
  end

  if conf.append and conf.append.json and #conf.append.json > 0
     and not skip_transform(resp_code, conf.append.if_status) then
    transform_ops.append_body = true
    transform_ops._need_transform = true
  end

  if conf.allow and conf.allow.json and #conf.allow.json > 0
     and not skip_transform(resp_code, conf.remove.if_status) then
    transform_ops.filter_body = true
    transform_ops._need_transform = true
  end

  if conf.transform and conf.transform.functions and #conf.transform.functions > 0
     and not skip_transform(resp_code, conf.transform.if_status) then
    transform_ops.transform_body = true
    transform_ops._need_transform = true
  end

  return transform_ops
end

function _M.transform_json_body(conf, buffered_data, transform_ops)
  local opts = { dots_in_keys = conf.dots_in_keys }
  local json_body, err = read_json_body(buffered_data)
  if not json_body then
    kong.log.debug("failed to decode the json body: ", err)
    return
  end

  -- remove key:value to body
  if transform_ops.remove_body then
    for _, name in iter(conf.remove.json) do
      navigate_and_apply(json_body, name, function (o, p) o[p] = nil end, opts)
    end
  end

  -- replace key:value to body
  if transform_ops.replace_body then
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

      if v ~= nil then
        navigate_and_apply(json_body, name, function (o, p)
          if o[p] then o[p] = v end
        end, opts)
      end
    end
  end

  -- add new key:value to body
  if transform_ops.add_body then
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

      if v ~= nil then
        local opts = {
          dots_in_keys = conf.dots_in_keys,
          create_inexistent_parent = true,
        }
        navigate_and_apply(json_body, name, function (o, p)
          if not o[p] then o[p] = v end
        end, opts)
      end
    end
  end

  -- append new key:value or value to existing key
  if transform_ops.append_body then
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
        navigate_and_apply(json_body, name, function (o, p) o[p] = append_value(o[p], v)
        end, opts)
      end
    end
  end

  -- filter body
  if transform_ops.filter_body then
    local filtered_json_body = {}
    local filtered = false
    for _, name in iter(conf.allow.json) do
      navigate_and_apply(json_body, name, function (o, p, ctx)
        local parent = init_json_path(filtered_json_body, ctx.paths)
        parent[p] = o[p]
        filtered = true
      end, opts)
    end

    if filtered then
      json_body = filtered_json_body
    end
  end

  local err
  -- perform arbitrary transformations on a json
  if transform_ops.transform_body then

    for _, fn in ipairs(get_transform_functions(conf)) do
      local ok, err_or_data = pcall(arbitrary_transform, conf, json_body, fn)

      if not ok then
        err = err_or_data
        break
      end

      json_body = err_or_data
    end

  end

  return cjson.encode(json_body), err
end

return _M
