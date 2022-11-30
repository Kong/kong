local exporter = require "kong.plugins.prometheus.exporter"
local kong = kong
local kong_meta = require "kong.meta"


exporter.init()


local plugin_name = "prometheus"
local PrometheusHandler = {
  PRIORITY = 13,
  VERSION  = kong_meta.version,
}


local function on_demond_enable()
  local worker_events = kong.worker_events
  local instance_count = 0
  local function update_instance_counters()
    instance_count = 0
    for plugin, err in kong.db.plugins:each() do
      if err then
        kong.log.crit("could not obtain list of plugins: ", err)
        return nil, err
      end

      if plugin.name == plugin_name then
        instance_count = instance_count + 1
        return
      end
    end
  end

  -- DB-less or DP.
  if kong.configuration.database == "off" then
    -- see if we have a cached config and prometheus plugin configured
    update_instance_counters()
    exporter.enable(instance_count > 0)

    worker_events.register(function(data)
      if data.entity.name ~= plugin_name then
        return
      end

      local operation = data.operation
      if operation == "create" then
        instance_count = instance_count + 1
      elseif operation == "delete" then
        instance_count = instance_count - 1
      end
      exporter.enable(instance_count > 0)
    end, "crud", "plugins")

  else
    -- disable exporter if we have no instance of plugin configured
    exporter.enable(instance_count > 0)
    worker_events.register(function()
      update_instance_counters()
      exporter.enable(instance_count > 0)
    end, "declarative", "flip_config")
  end
end


function PrometheusHandler.init_worker()
  exporter.init_worker()
  on_demond_enable()
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
