local reports = require "kong.reports"

return {
  ["/reports/send-ping"] = {
    POST = function()
      reports.send_ping()
      kong.response.exit(200, { message = "ok" })
    end,
  },
}
