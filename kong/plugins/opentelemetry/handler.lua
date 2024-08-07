
local otel_traces = require "kong.plugins.opentelemetry.traces"
local otel_logs = require "kong.plugins.opentelemetry.logs"
local dynamic_hook = require "kong.dynamic_hook"
local o11y_logs = require "kong.observability.logs"
local kong_meta = require "kong.meta"



local OpenTelemetryHandler = {
  VERSION = kong_meta.version,
  PRIORITY = 14,
}


function OpenTelemetryHandler:configure(configs)
  if configs then
    for _, config in ipairs(configs) do
      if config.logs_endpoint then
        dynamic_hook.hook("observability_logs", "push", o11y_logs.maybe_push)
        dynamic_hook.enable_by_default("observability_logs")
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
