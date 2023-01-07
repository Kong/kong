local exporter = require "kong.plugins.prometheus.exporter"
local kong = kong
local kong_meta = require "kong.meta"

local keys = require('pl.tablex').keys
local sort = table.sort
local concat = table.concat

exporter.init()


local PrometheusHandler = {
  PRIORITY = 13,
  VERSION  = kong_meta.version,
}

function PrometheusHandler.init_worker()
  exporter.init_worker()
end

local http_subsystem = ngx.config.subsystem == "http"


function PrometheusHandler.log(self, conf)
  local message = kong.log.serialize()

  local serialized = {}
  if conf.per_consumer and message.consumer ~= nil then
    serialized.consumer = message.consumer.username
  end

  if conf.status_code_metrics then
    if http_subsystem and message.response then
      serialized.status_code = message.response.status
    elseif not http_subsystem and message.session then
      serialized.status_code = message.session.status
    end
  end

  local tags = {}
  if conf.expose_tags.from_service and message.service and message.service.tags then
    for i = 1, #message.service.tags do
      tags[message.service.tags[i]] = true
    end
  end
  if conf.expose_tags.from_route and message.route and message.route.tags then
    for i = 1, #message.route.tags do
      tags[message.route.tags[i]] = true
    end
  end
  if conf.expose_tags.from_consumer and message.consumer and message.consumer.tags then
    for i = 1, #message.consumer.tags do
      tags[message.consumer.tags[i]] = true
    end
  end
  tags = keys(tags)
  sort(tags)
  serialized.tags = concat(tags, ",")

  if conf.bandwidth_metrics then
    if http_subsystem then
      serialized.egress_size = message.response and tonumber(message.response.size)
      serialized.ingress_size = message.request and tonumber(message.request.size)
    else
      serialized.egress_size = message.response and tonumber(message.session.sent)
      serialized.ingress_size = message.request and tonumber(message.session.received)
    end
  end

  if conf.latency_metrics then
    serialized.latencies = message.latencies
  end

  if conf.upstream_health_metrics then
    exporter.set_export_upstream_health_metrics(true)
  end

  exporter.log(message, serialized)
end


return PrometheusHandler
