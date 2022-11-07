-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local constant = require "kong.plugins.mocking.jsonschema-mocker.constants"

local random = math.random
local type = type
local floor = math.floor

local _M = {}

function _M.generate(schema, opts)
  if schema and type(schema.example) == "number" then
    return floor(schema.example)
  end

  opts = opts or {}
  opts.default_minimum = opts.default_minimum or constant.DEFAULT_MINIMUM
  opts.default_maximum = opts.default_maximum or constant.DEFAULT_MAXIMUM

  local minimum = schema.minimum or opts.default_minimum
  local maximum = schema.maximum or opts.default_maximum
  local exclusive_minimum = schema.exclusiveMinimum == true
  local exclusive_maximum = schema.exclusiveMaximum == true
  if exclusive_minimum then
    minimum = minimum + 1
  end
  if exclusive_maximum then
    maximum = maximum - 1
  end

  return random(minimum, maximum)
end

return _M
