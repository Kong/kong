-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson = require("cjson.safe").new()
local jsonschema = require "resty.ljsonschema"
local split = require("kong.tools.utils").split

cjson.decode_array_with_array_mt(true)

local _M = {}


function _M.generate(schema, options)
  do
    local t, err = cjson.decode(schema)
    if not t then
      return nil, "failed decoding schema: " .. tostring(err)
    end
    schema = t
  end

  local ok, func, err = pcall(jsonschema.generate_validator, schema, options)
  if not ok then
    return nil, "failed to generate schema validator: " .. tostring(func)
  end

  if not func then
    return nil, "failed to generate schema validator: " .. tostring(err)
  end

  return func
end


do
  -- walk the schema and return the referenced entry
  local function find_reference(schema, ref, seen)
    if type(ref) ~= "string" then
      return nil, "expected ref to be a string"
    end

    if type(schema) ~= "table" then
      return nil, "expected schema to be a table"
    end

    -- check+track recursiveness
    if seen[ref] then
      return nil, "recursive references"
    else
      seen[ref] = true
    end

    local segments = split(ref, "/")
    if type(segments) ~= "table" then
      return nil, "couldn't split the reference segments"
    end

    if segments[1] ~= "#" then
      return nil, "expected a $ref value to start with '#/'"
    else
      table.remove(segments, 1)
    end

    local target = schema
    for _, segment in ipairs(segments) do
      if type(target) ~= "table" then
        return nil, "reference deeper than structure"
      end
      target = target[segment]
      if target == nil then
        return nil, "reference not found"
      end

      if type(target) == "table" and target["$ref"] then
        local err
        target, err = find_reference(schema, target["$ref"], seen)
        if target == nil then
          return nil, err
        end
      end
    end

    return target
  end

  -- validate the schema has a top-level 'type' property. But take into account that
  -- the top-level might actually be a reference first. So the first non-reference
  -- object must have a 'type' field
  local function has_type(s)
    if s.type then
      return true -- found a type, so we're ok
    end

    -- we don't have a type, but it might be a reference...
    local ref = s["$ref"]
    if not ref then
      return false -- so neither a type, nor a reference, so that's not ok
    end

    -- find the referenced target...
    local target = find_reference(s, ref, {})

    -- check the target for the type field
    if type(target) ~= "table" then
      return false
    elseif not target.type then
      return false
    end

    return true
  end


  function _M.validate(schema_conf, is_parameter)
    local schema
    do
      local t, err = cjson.decode(schema_conf)
      if not t then
        return nil, "failed decoding schema: " .. tostring(err)
      end
      schema = t
    end

    local ok, err = jsonschema.jsonschema_validator(schema)
    if not ok then
      return ok, "not a valid JSONschema draft 4 schema: " .. tostring(err)
    end

    local f
    f, err = _M.generate(schema_conf)
    if not f then
      return nil, err
    end

    ok, err = pcall(f, {})  --run it once with an empty object
    if not ok then
      return nil, err
    end

    if is_parameter and not has_type(schema) then
      return nil, "the JSONschema is missing a top-level 'type' property"
    end

    return true
  end
end

return _M
