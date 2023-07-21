-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local str_upper = string.upper

local constants = {
  CONTENT_METHODS = {
    POST = true,
    PUT = true,
    PATCH = true,
  }
}

setmetatable(constants.CONTENT_METHODS, {
  __index = function(t, key)
    return rawget(t, str_upper(key))
  end
})

return constants
