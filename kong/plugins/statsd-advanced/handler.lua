-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local statsd_handler = require "kong.plugins.statsd.handler"

local kong = kong

local handler = require("kong.tools.table").cycle_aware_deep_copy(statsd_handler)
local logging_flag = false
local log = handler.log

function handler:log(conf)
  if not logging_flag then
    kong.log.warn("the statsd-advanced plugin has been deprecated and will be removed at 4.0" ..
      "please migrate to statsd")
    logging_flag = true
  end

  log(self, conf)
end

return handler
