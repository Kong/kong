local PDKLoggerHandler =  {
  VERSION = "0.1-t",
  PRIORITY = 1000,
}

local plugin_name = "pdk-logger"
local attributes = { some_key = "some_value", some_other_key = "some_other_value"}


function PDKLoggerHandler:access(conf)
  local message_type = "access_phase"
  local message = "hello, access phase"
  -- pass both optional arguments (message and attributes)
  local ok, err = kong.telemetry.log(plugin_name, conf, message_type, message, attributes)
  if not ok then
    kong.log.err(err)
  end
end


function PDKLoggerHandler:header_filter(conf)
  local message_type = "header_filter_phase"
  local message = "hello, header_filter phase"
  -- no attributes
  local ok, err = kong.telemetry.log(plugin_name, conf, message_type, message, nil)
  if not ok then
    kong.log.err(err)
  end
end


function PDKLoggerHandler:log(conf)
  local message_type = "log_phase"
  -- no message
  local ok, err = kong.telemetry.log(plugin_name, conf, message_type, nil, attributes)
  if not ok then
    kong.log.err(err)
  end

  message_type = "log_phase_2"
  -- no attributes and no message
  ok, err = kong.telemetry.log(plugin_name, conf, message_type, nil, nil)
  if not ok then
    kong.log.err(err)
  end
end


return PDKLoggerHandler
