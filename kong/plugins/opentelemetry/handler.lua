-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local otel_traces = require "kong.plugins.opentelemetry.traces"
local otel_logs = require "kong.plugins.opentelemetry.logs"
local dynamic_hook = require "kong.dynamic_hook"
local o11y_logs = require "kong.observability.logs"

--[= xxx EE
local kong_meta = require "kong.meta"
--]=]


local OpenTelemetryHandler = {
  VERSION = kong_meta.core_version,
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
