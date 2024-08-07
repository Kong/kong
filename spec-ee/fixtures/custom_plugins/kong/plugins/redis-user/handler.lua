-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local kong = kong
local redis = require "kong.enterprise_edition.tools.redis.v2"

local RedisUser = {
  PRIORITY = 0,
  VERSION = "1.0",
}


function RedisUser:access(conf)
  local red, err = redis.connection(conf.redis)
  if not red or err then
    return kong.response.exit(500, "Redis not connected. Reason " .. err)
  end

  local value_to_set = kong.request.get_header(conf.header_name)
  if not value_to_set then
    return kong.response.exit(400, "Redis value to set not present in header: " .. conf.header_name)
  end

  red:set(conf.redis_key, value_to_set)

  return kong.response.exit(200, "Ok - good!")
end


return RedisUser
