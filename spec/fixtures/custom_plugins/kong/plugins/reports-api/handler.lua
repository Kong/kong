-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local ReportsApiHandler = {
  PRIORITY = 1000
}

function ReportsApiHandler:preread()
  local reports = require "kong.reports"
  reports._sync_counter()
  reports.send_ping()
  ngx.print("ok")
  ngx.exit(200)
end


return ReportsApiHandler
