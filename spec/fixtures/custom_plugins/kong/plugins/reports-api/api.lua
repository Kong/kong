local reports = require "kong.reports"

return {
  ["/reports/send-ping"] = {
    POST = function()
      reports._sync_counter()
      reports.send_ping()
      kong.response.exit(200, { message = "ok" })
    end,
  },
}
