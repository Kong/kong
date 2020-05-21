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
