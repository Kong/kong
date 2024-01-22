-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local kong_meta = require "kong.meta"

local ReconfigurationCompletionHandler = {
  VERSION = "1.0",
  PRIORITY = 2000000,
}


function ReconfigurationCompletionHandler:rewrite(conf)
  local status = "unknown"
  local if_kong_configuration_version = kong.request and kong.request.get_header('if-kong-configuration-version')
  if if_kong_configuration_version then
    if if_kong_configuration_version ~= conf.version then
      return kong.response.error(
        503,
        "Service Unavailable",
        {
          ["X-Kong-Reconfiguration-Status"] = "pending",
          ["Retry-After"] = tostring((kong.configuration.worker_state_update_frequency or 1) + 1),
        }
      )
    else
      status = "complete"
    end
  end
  kong.response.set_header("X-Kong-Reconfiguration-Status", status)
end

return ReconfigurationCompletionHandler
