-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local reports = require "kong.reports"
local constants = require "kong.constants"


return {
  ["/reports/send-ping"] = {
    POST = function(self)
      -- if a port was passed, patch it in constants.REPORTS so
      -- that tests can change the default reports port
      if self.params.port then
        constants.REPORTS.STATS_PORT = self.params.port
      end

      reports._sync_counter()
      reports.send_ping()
      kong.response.exit(200, { message = "ok" })
    end,
  },
}
