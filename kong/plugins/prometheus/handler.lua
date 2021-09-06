local prometheus = require "kong.plugins.prometheus.exporter"
local kong = kong


prometheus.init()


local PrometheusHandler = {
  PRIORITY = 13,
  VERSION  = "1.4.0",
}

function PrometheusHandler.init_worker()
  prometheus.init_worker()
end


function PrometheusHandler.log(self, conf)
  local message = kong.log.serialize()

  local serialized = {}
  if conf.per_consumer and message.consumer ~= nil then
    serialized.consumer = message.consumer.username
  end
  if not conf.expose_services_tags and message.service ~= nil then
    message.service.tags = nil
  end
  if not conf.expose_routes_tags and message.route ~= nil then
    message.route.tags = nil
  end

  prometheus.log(message, serialized)
end


return PrometheusHandler
