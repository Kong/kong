
local otel_traces = require "kong.plugins.opentelemetry.traces"
local otel_logs = require "kong.plugins.opentelemetry.logs"
local otel_utils = require "kong.plugins.opentelemetry.utils"
local dynamic_hook = require "kong.dynamic_hook"
local o11y_logs = require "kong.observability.logs"
local kong_meta = require "kong.meta"

local _log_prefix = otel_utils._log_prefix
local ngx_log = ngx.log
local ngx_WARN = ngx.WARN


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
  -- Read resource attributes variable
  local options = {}
  if conf.resource_attributes then
    local compiled, err = otel_utils.compile_resource_attributes(conf.resource_attributes)
    if not compiled then
      ngx_log(ngx_WARN, _log_prefix, "resource attributes template failed to compile: ", err)
    end
    options.compiled_resource_attributes = compiled
  end

  -- Traces
  if conf.traces_endpoint then
    otel_traces.log(conf, options)
  end

  -- Logs
  if conf.logs_endpoint then
    otel_logs.log(conf, options)
  end
end


return OpenTelemetryHandler
