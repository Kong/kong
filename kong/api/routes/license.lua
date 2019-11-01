local kong = kong

return {
  ["/license/report"] = {
    GET = function()
      return kong.response.exit(200, kong.sales_counters:get_license_report())
    end
  }
}
