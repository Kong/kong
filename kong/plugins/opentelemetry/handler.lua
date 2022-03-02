local subsystem = ngx.config.subsystem
local pb = require "pb"
local protoc = require "protoc"
local readfile = require "pl.utils".readfile

local OpenTelemetryHandler = {
  VERSION = "0.0.1",
  -- We want to run first so that timestamps taken are at start of the phase
  -- also so that other plugins might be able to use our structures
  PRIORITY = 100000,
}

function OpenTelemetryHandler:init_worker()
  local p = protoc.new()
  -- TODO: rel path
  local trace_proto = assert(readfile("/kong/kong/pdk/tracer/trace.proto"))
  assert(p:load(trace_proto))
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
