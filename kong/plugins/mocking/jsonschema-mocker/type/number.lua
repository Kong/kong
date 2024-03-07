-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local constant = require "kong.plugins.mocking.jsonschema-mocker.constants"

local type = type
local floor = math.floor
local random = math.random

local _M = {}

function _M.generate(schema, opts)
  if schema and type(schema.example) == "number" then
    return schema.example
  end

  opts = opts or {}
  opts.default_minimum = opts.default_minimum or constant.DEFAULT_MINIMUM
  opts.default_maximum = opts.default_maximum or constant.DEFAULT_MAXIMUM

  local minimum = schema.minimum or opts.default_minimum
  local maximum = schema.maximum or opts.default_maximum
  local delta = maximum - minimum

  return minimum + floor(random() * delta * 100) / 100
end

return _M
