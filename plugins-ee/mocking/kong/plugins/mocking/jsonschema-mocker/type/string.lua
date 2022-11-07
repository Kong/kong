-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local constant = require "kong.plugins.mocking.jsonschema-mocker.constants"
local new_tab = require "table.new"

local type = type
local date = os.date
local random = math.random
local concat = table.concat


local _M = {}

local formatters = {
  ["date"] = function()
    return date("!%Y-%m-%d")
  end,
  ["date-time"] = function()
    return date("!%Y-%m-%dT%H:%M:%SZ")
  end,
}

local function random_character()
  local charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890"
  local i = random(1, #charset)
  return charset:sub(i, i)
end

local function random_string(min_length, max_length)
  local length = random(min_length, max_length)
  local buf = new_tab(length, 0)
  for i = 1, length do
    buf[i] = random_character()
  end

  return concat(buf)
end

function _M.generate(schema, opts)
  if schema and type(schema.example) == "string" then
    return schema.example
  end

  opts = opts or {}
  opts.default_min_length = opts.default_min_length or constant.DEFAULT_STRING_MIN_LENGTH
  opts.default_max_length = opts.default_max_length or constant.DEFAULT_STRING_MAX_LENGTH

  local min_length = type(schema.minLength) == "number" and schema.minLength or opts.default_min_length
  local max_length = type(schema.maxLength) == "number" and schema.maxLength or opts.default_max_length

  local formatter = formatters[schema.format]
  if formatter then
    return formatter()
  end

  return random_string(min_length, max_length)
end

return _M
