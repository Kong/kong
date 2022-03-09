local subsystem = ngx.config.subsystem
local load_pb = require("kong.plugins.opentelemetry.otlp").load_pb
local to_pb = require("kong.plugins.opentelemetry.otlp").to_pb
local to_otlp_span = require("kong.plugins.opentelemetry.otlp").to_otlp_span
local otlp_export_request = require("kong.plugins.opentelemetry.otlp").otlp_export_request
local new_tab = require "table.new"
local insert = table.insert


local OpenTelemetryHandler = {
  VERSION = "0.0.1",
  -- We want to run first so that timestamps taken are at start of the phase
  -- also so that other plugins might be able to use our structures
  PRIORITY = 100000,
}

-- cache exporter instances
local exporter_cache = setmetatable({}, { __mode = "k" })

function OpenTelemetryHandler:init_worker()
  assert(load_pb())

  -- patch db query
end


-- collect trace and spans
function OpenTelemetryHandler:log(conf) -- luacheck: ignore 212
  
end


return OpenTelemetryHandler
