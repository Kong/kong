-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local split = require("pl.utils").split
local utils = require("kong.tools.utils")
local clone = require "table.clone"

local type = type
local pairs = pairs
local assert = assert
local table_remove = table.remove

local _M = {}

local function walk_tree(path, tree)
  assert(type(path) == "string", "path must be a string")
  assert(type(tree) == "table", "tree must be a table")

  local segments = split(path, "%/")
  if path == "/" then
    -- top level reference, to full document
    return tree
  elseif segments[1] == "" then
    -- starts with a '/', so remove first empty segment
    table_remove(segments, 1)
  else
    -- first segment is not empty, so we had a relative path
    return nil, "only absolute references are supported, not " .. path
  end

  local position = tree
  for i = 1, #segments do
    position = position[segments[i]]
    if position == nil then
      return nil, "not found"
    end
    if i < #segments and type(position) ~= "table" then
      return nil, "next level cannot be dereferenced, expected table, got " .. type(position)
    end
  end
  return position
end

local function dereference_single_level(full_spec, schema, parent_ref)
  for key, value in pairs(schema) do
    local curr_parent_ref = clone(parent_ref)
    while type(value) == "table" and value["$ref"] do
      local reference = value["$ref"]
      if curr_parent_ref[reference] then
        return nil, "recursion detected in schema dereferencing"
      end
      curr_parent_ref[reference] = true

      local file, path = reference:match("^(.-)#(.-)$")
      if not file then
        return nil, "bad reference: " .. reference
      elseif file ~= "" then
        return nil, "only local references are supported, not " .. reference
      end

      local ref_target, err = walk_tree(path, full_spec)
      if not ref_target then
        return nil, "failed dereferencing schema: " .. err
      end
      value = utils.cycle_aware_deep_copy(ref_target)
      schema[key] = value
    end

    if type(value) == "table" then
      local ok, err = dereference_single_level(full_spec, value, curr_parent_ref)
      if not ok then
        return nil, err
      end
    end
  end

  return schema
end

local function get_dereferenced_schema(full_spec)
  -- wrap to also deref top level
  local schema = utils.cycle_aware_deep_copy(full_spec)
  local wrapped_schema, err = dereference_single_level(full_spec, { schema }, {})
  if not wrapped_schema then
    return nil, err
  end

  return wrapped_schema[1]
end


_M.dereference = function(schema)
  return get_dereferenced_schema(schema)
end

return _M
