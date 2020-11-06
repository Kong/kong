-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local kong = kong


local DEFAULT_RESPONSE = {
  [401] = "Unauthorized",
  [404] = "Not found",
  [405] = "Method not allowed",
  [500] = "An unexpected error occurred",
  [502] = "Bad Gateway",
  [503] = "Service unavailable",
}


local RequestTerminationHandler = {}


RequestTerminationHandler.PRIORITY = 2
RequestTerminationHandler.VERSION = "2.0.1"


function RequestTerminationHandler:access(conf)
  local status  = conf.status_code
  local content = conf.body

  if content then
    local headers = {
      ["Content-Type"] = conf.content_type
    }

    return kong.response.exit(status, content, headers)
  end

  local message = conf.message or DEFAULT_RESPONSE[status]
  return kong.response.exit(status, message and { message = message } or nil)
end


return RequestTerminationHandler
