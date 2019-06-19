local cjson = require "cjson.safe"
local jsonschema = require "resty.ljsonschema"


local _M = {}

local function decode(data)
  -- test decode with array_mt, to not change global settings
  local t = cjson.decode("[]")
  local status = getmetatable(t) == cjson.array_mt

  cjson.decode_array_with_array_mt(true)
  local schema, err = cjson.decode(data)
  cjson.decode_array_with_array_mt(status)  -- restore old state

  return schema, err
end


function _M.generate(plugin_conf)
  local schema = plugin_conf.body_schema

  do
    local t, err = decode(schema)
    if not t then
      return nil, "failed decoding schema: " .. tostring(err)
    end
    schema = t
  end

  local ok, func, err = pcall(jsonschema.generate_validator, schema)
  if not ok then
    return nil, "failed to generate schema validator: " .. tostring(func)
  end

  if not func then
    return nil, "failed to generate schema validator: " .. tostring(err)
  end

  return func
end


function _M.validate(entity)
  local config = entity.config
  local schema = config.body_schema

  do
    local t, err = decode(schema)
    if not t then
      return nil, "failed decoding schema: " .. tostring(err)
    end
    schema = t
  end

  local ok, err = jsonschema.jsonschema_validator(schema)
  if not ok then
    return ok, "Not a valid JSONschema draft 4 schema: " .. tostring(err)
  end

  local f
  f, err = _M.generate(config)
  if not f then
    return nil, err
  end

  ok, err = pcall(f, {})  --run it once with an empty object
  if not ok then
    return nil, err
  end

  return true
end

return _M
