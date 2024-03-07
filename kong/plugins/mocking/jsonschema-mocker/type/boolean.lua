-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local type = type
local random = math.random

local _M = {}

function _M.generate(schema, opts)
  if schema and type(schema.example) == "boolean" then
    return schema.example
  end

  return random(0, 1) == 0
end

return _M
