local subsystem = ngx.config.subsystem
local pb = require "pb"
local protoc = require "protoc"
local readfile = require "pl.utils".readfile
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
  local p = protoc.new()
  -- TODO: rel path
  local otlp_proto = assert(readfile("/kong/kong/plugins/opentelemetry/otlp.proto"))
  assert(p:load(otlp_proto))
end

-- different instruments based on Nginx subsystem
if subsystem == "http" then

  function OpenTelemetryHandler:access(conf) -- luacheck: ignore 212
    
  end


  function OpenTelemetryHandler:header_filter(conf) -- luacheck: ignore 212
    
  end


  function OpenTelemetryHandler:body_filter(conf) -- luacheck: ignore 212
  end

elseif subsystem == "stream" then
-- TODO:
end


-- collect trace and spans
function OpenTelemetryHandler:log(conf) -- luacheck: ignore 212
  
end


return OpenTelemetryHandler
