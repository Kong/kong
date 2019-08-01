local prometheus = require "kong.plugins.prometheus.exporter"
local basic_serializer = require "kong.plugins.log-serializers.basic"


local kong = kong
local timer_at = ngx.timer.at


prometheus.init()


local function log(premature, message)
  if premature then
    return
  end

  prometheus.log(message)
end


local PrometheusHandler = {
  PRIORITY = 13,
  VERSION  = "0.4.1",
}


function PrometheusHandler:log(_)
  local message = basic_serializer.serialize(ngx)
  local ok, err = timer_at(0, log, message)
  if not ok then
    kong.log.err("failed to create timer: ", err)
  end
end


return PrometheusHandler
