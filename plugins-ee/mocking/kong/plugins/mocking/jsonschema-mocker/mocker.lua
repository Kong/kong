-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local constant = require "kong.plugins.mocking.jsonschema-mocker.constants"
local boolean_generator = require "kong.plugins.mocking.jsonschema-mocker.type.boolean"
local integer_generator = require "kong.plugins.mocking.jsonschema-mocker.type.integer"
local number_generator = require "kong.plugins.mocking.jsonschema-mocker.type.number"
local string_generator = require "kong.plugins.mocking.jsonschema-mocker.type.string"
local utils = require "kong.tools.utils"
local cjson = require "cjson"

local type = type
local table_insert = table.insert
local pairs = pairs
local ipairs = ipairs
local random = math.random

local _M = {}


local function table_merge(dst, src, override)
  local stack = {}
  local node1 = dst
  local node2 = src
  while (true) do
    for k, v in pairs(node2) do
      if (type(v) == "table" and type(node1[k]) == "table") then
        table_insert(stack, { node1[k], node2[k] })
      elseif override == true or node1[k] == nil then
        node1[k] = v
      end
    end
    local stack_n = #stack
    if (stack_n > 0) then
      local t = stack[stack_n]
      node1, node2 = t[1], t[2]
      stack[stack_n] = nil
    else
      break
    end
  end
  return dst
end

local mock

local generator = {
  string = string_generator.generate,
  number = number_generator.generate,
  integer = integer_generator.generate,
  boolean = boolean_generator.generate,
  array = function(schema, opts)
    opts = opts or {}
    opts.default_min_items = opts.default_min_items or constant.DEFAULT_MIN_ITEMS
    opts.default_max_items = opts.default_min_items or constant.DEFAULT_MAX_ITEMS

    if schema and type(schema.example) == "table" then
      return schema.example
    end

    local min_items = type(schema.minItems) == "number" and schema.minItems or opts.default_min_items
    local max_items = type(schema.maxItems) == "number" and schema.maxItems or opts.default_max_items

    local value = {}
    setmetatable(value, cjson.array_mt)
    if schema.items then
      local n = random(min_items, max_items)
      for i = 1, n do
        table_insert(value, mock(schema.items))
      end
    end
    return value
  end,
  object = function(schema, opts)
    if schema and type(schema.example) == "table" then
      return schema.example
    end

    local value = {}
    if schema.properties then
      for k, v in pairs(schema.properties) do
        value[k] = mock(v)
      end
    end
    return value
  end,
}

setmetatable(generator, {
  __index = function(table, key)
    return function()
      return "Unknown Type: " .. key
    end
  end
})

mock = function(schema)
  if type(schema) ~= "table" then
    error("invalid type of schema")
  end

  schema = utils.cycle_aware_deep_copy(schema)

  while schema.allOf or schema.oneOf do
    local resolved_schema = {}
    local allOf = schema.allOf
    local oneOf = schema.oneOf

    schema.allOf = nil
    schema.oneOf = nil

    if type(allOf) == "table" then
      for _, v in ipairs(allOf) do
        resolved_schema = table_merge(resolved_schema, v, true)
      end
    end

    if type(oneOf) == "table" then
      resolved_schema = table_merge(resolved_schema, oneOf[random(1, #oneOf)], true)
    end

    schema = table_merge(schema, resolved_schema)
  end

  if type(schema.enum) == "table" then
    return schema.enum[random(1, #schema.enum)]
  end

  local typ = schema.type
  if typ == nil then
    typ = "object"
  end

  if type(typ) ~= "string" then
    error("invalid type of schema.type")
  end

  return generator[typ](schema)
end

_M.mock = mock

return _M
