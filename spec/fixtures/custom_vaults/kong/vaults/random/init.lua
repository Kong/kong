-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local utils         = require "kong.tools.utils"

local function get(conf, resource, version)
  -- Return a random string every time
  kong.log.err("get() called")
  return utils.random_string()
end


return {
  VERSION = "1.0.0",
  get = get,
}
