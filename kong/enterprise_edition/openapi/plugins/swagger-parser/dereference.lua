-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local split = require "pl.stringx".split
local utils = require "kong.tools.utils"
local clone = require "table.clone"

local type = type
local pairs = pairs
local byte = string.byte
local sub = string.sub

local _M = {}


local function is_ref(obj)
  return type(obj) == "table" and obj["$ref"]
end


local function has_ref(schema)
  if is_ref(schema) then
    return true
  end

  if type(schema) == "table" then
    for _, value in pairs(schema) do
      if has_ref(value) then
        return true
      end
    end
  end

  return false
end


local function by_ref(obj, ref)
  if type(ref) ~= "string" then
    return nil, "invalid ref: ref must be a string"
  end
  if byte(ref) ~= byte("/") then
    return nil, "invalid ref: " .. ref
  end

  if ref == "/" then
    -- root reference
    return obj
  end

  local segments = split(sub(ref, 2), "/")

  for i = 1, #segments do
    local segment = segments[i]
    if obj[segment] == nil then
      return nil, "invalid ref: " .. segment
    end
    obj = obj[segment]
  end

  return obj
end


local function is_circular(refs, schema)
  local visited = {}

  while is_ref(schema) do
    local ref = schema["$ref"]
    if visited[ref] then
      return true
    end

    visited[ref] = true
    ref = sub(ref, 2) -- remove #
    schema = by_ref(refs, ref)
  end

  return false
end

local reference_mt = {}
function reference_mt:is_ref()
  return true
end

local function resolve_ref(spec, schema, opts, parent_ref)
  if type(schema) ~= "table" then
    return schema
  end

  for key, value in pairs(schema) do
    if key == "schema" then
      if has_ref(value) then
        -- attach a metatable to indicate it's a reference schema
        setmetatable(value, {
          __index = reference_mt,
          refs = {
            definitions = spec.definitions,
            components = spec.components,
          }
        })
        if is_circular(spec, value) then
          return nil, "recursion detected in schema dereferencing: " .. value["$ref"]
        end
      end

    else
      local curr_parent_ref = clone(parent_ref)
      while is_ref(value) do
        local ref = value["$ref"]
        if byte(ref, 1) ~= byte("#") then
          return nil, "only local references are supported, not " .. ref
        end

        local maximum_dereference = opts.dereference and opts.dereference.maximum_dereference or 0
        if curr_parent_ref[ref] and maximum_dereference == 0 then
          return nil, "recursion detected in schema dereferencing"
        end
        local derefer_cnt = curr_parent_ref[ref]
        if not derefer_cnt or derefer_cnt < maximum_dereference then
          local ref_target, err = by_ref(spec, sub(ref, 2))
          if not ref_target then
            return nil, "failed dereferencing schema: " .. err
          end
          value = utils.cycle_aware_deep_copy(ref_target)
          schema[key] = value

        else
          schema[key] = nil
          break
        end
        curr_parent_ref[ref] = (derefer_cnt or 0) + 1
      end

      if type(value) == "table" then
        local ok, err = resolve_ref(spec, value, opts, curr_parent_ref)
        if not ok then
          return nil, err
        end
      end
    end
  end

  return schema
end

_M.resolve = function(spec, opts)
  local resolved_paths, err = resolve_ref(spec, spec.paths, opts, {})
  if err then
    return nil, err
  end

  spec.paths = resolved_paths

  return spec
end

_M.dereference = function(schema, opts, refs)
  local wraps_result, err = resolve_ref(refs, { schema }, opts, {})
  if err then
    return nil, err
  end
  return wraps_result[1]
end

return _M
