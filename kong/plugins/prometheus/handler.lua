local prometheus = require "kong.plugins.prometheus.exporter"
local basic_serializer = require "kong.plugins.log-serializers.basic"


prometheus.init()


local PrometheusHandler = {
  PRIORITY = 13,
  VERSION  = "0.9.0",
}

function PrometheusHandler.init_worker()
  prometheus.init_worker()
end


function PrometheusHandler.log()
  local message = basic_serializer.serialize(ngx)
  prometheus.log(message)
end


return PrometheusHandler
