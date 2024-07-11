
local otel_traces = require "kong.plugins.opentelemetry.traces"
local otel_logs = require "kong.plugins.opentelemetry.logs"
local dynamic_hook = require "kong.dynamic_hook"
local o11y_logs = require "kong.observability.logs"
local kong_meta = require "kong.meta"



local OpenTelemetryHandler = {
  VERSION = kong_meta.version,
  PRIORITY = 14,
}


local function log_global_metrics(premature)
  if (premature) then
    return
  end

  -- Gather shm and worker metrics
  local metrics = kong.node.get_memory_stats()
  local attributes = {}
  for name, data in pairs(metrics.lua_shared_dicts) do
    attributes["lua_shared_dict." .. name .. ".allocated_slabs"] = data.allocated_slabs
    attributes["lua_shared_dict." .. name .. ".capacity"] = data.capacity
  end
  for i, data in ipairs(metrics.workers_lua_vms) do
    attributes["worker." .. tostring(i-1) .. ".http_allocated_gc"] = data.http_allocated_gc
    attributes["worker." .. tostring(i-1) .. ".pid"] = data.pid
  end
  -- Gather nginx statistics
  local nginx_statistics = kong.nginx.get_statistics()
  local subsystem = ngx.config.subsystem
  attributes[subsystem .. ".connections_active"] = nginx_statistics.connections_active
  attributes[subsystem .. ".connections_accepted"] = nginx_statistics.connections_accepted
  attributes[subsystem .. ".connections_handled"] = nginx_statistics.connections_handled
  attributes[subsystem .. ".connections_reading"] = nginx_statistics.connections_reading
  attributes[subsystem .. ".connections_writing"] = nginx_statistics.connections_writing
  attributes[subsystem .. ".connections_waiting"] = nginx_statistics.connections_waiting
  attributes[subsystem .. ".total"] = nginx_statistics.total_requests

  -- Send log message with metrics data
  kong.telemetry.log("kong", {}, "global_metrics", "global metrics", attributes)
end


function OpenTelemetryHandler:init_worker()
  if ngx.worker.id() == 0 then
    kong.timer:named_every("global metrics", 1, log_global_metrics)
  end
end


function OpenTelemetryHandler:configure(configs)
  if configs then
    for _, config in ipairs(configs) do
      if config.logs_endpoint then
        dynamic_hook.hook("observability_logs", "push", o11y_logs.maybe_push)
        dynamic_hook.enable_by_default("observability_logs")
        break
      end
    end
  end
end


function OpenTelemetryHandler:access(conf)
  -- Traces
  if conf.traces_endpoint then
    otel_traces.access(conf)
  end
end


function OpenTelemetryHandler:header_filter(conf)
  -- Traces
  if conf.traces_endpoint then
    otel_traces.header_filter(conf)
  end
end


function OpenTelemetryHandler:log(conf)
  -- Traces
  if conf.traces_endpoint then
    otel_traces.log(conf)
  end

  -- Logs
  if conf.logs_endpoint then
    otel_logs.log(conf)
  end
end


return OpenTelemetryHandler
