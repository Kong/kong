-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local statsd_handler  = require "kong.vitals.prometheus.statsd.handler"
local log_helper      = require "kong.plugins.statsd-advanced.log_helper"


local StatsdHandler = {
  PRIORITY = 11,
  VERSION = "0.2.2"
}


function StatsdHandler:log(conf)
  log_helper:log(statsd_handler, conf, ngx.status)
end


return StatsdHandler
