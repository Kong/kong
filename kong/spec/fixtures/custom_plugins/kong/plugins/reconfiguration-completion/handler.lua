local kong_meta = require "kong.meta"

local ReconfigurationCompletionHandler = {
  VERSION = kong_meta.version,
  PRIORITY = 2000000,
}


function ReconfigurationCompletionHandler:rewrite(conf)
  local status = "unknown"
  local if_kong_configuration_version = kong.request and kong.request.get_header('if-kong-configuration-version')
  if if_kong_configuration_version then
    if if_kong_configuration_version ~= conf.version then
      return kong.response.error(
        503,
        "Service Unavailable",
        {
          ["X-Kong-Reconfiguration-Status"] = "pending",
          ["Retry-After"] = tostring((kong.configuration.worker_state_update_frequency or 1) + 1),
        }
      )
    else
      status = "complete"
    end
  end
  kong.response.set_header("X-Kong-Reconfiguration-Status", status)
end

return ReconfigurationCompletionHandler
