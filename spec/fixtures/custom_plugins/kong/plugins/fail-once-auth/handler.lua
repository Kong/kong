-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

-- a plugin fixture to force one authentication failure

local FailOnceAuth =  {
  VERSION = "0.1-t",
  PRIORITY = 1000,
}

local failed = {}

function FailOnceAuth:access(conf)
  if not failed[conf.service_id] then
    failed[conf.service_id] = true
    return kong.response.exit(401, { message = conf.message })
  end
end

return FailOnceAuth
