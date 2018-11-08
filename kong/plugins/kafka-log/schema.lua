local types = require "kong.plugins.kafka-log.types"
local utils = require "kong.tools.utils"

--- Validates value of `bootstrap_servers` field.
local function check_bootstrap_servers(values)
  if values and 0 < #values then
    for _, value in ipairs(values) do
      local server = types.bootstrap_server(value)
      if not server then
        return false, "invalid bootstrap server value: " .. value
      end
    end
    return true
  end
  return false, "bootstrap_servers is required"
end

--- (Re)assigns a unique id on every configuration update.
-- since `uuid` is not a part of the `fields`, clients won't be able to change it
local function regenerate_uuid(schema, plugin_t, dao, is_updating)
  plugin_t.uuid = utils.uuid()
  return true
end

return {
  fields = {
    bootstrap_servers = { type = "array", required = true, func = check_bootstrap_servers },
    topic = { type = "string", required = true },
    timeout = { type = "number", default = 10000 },
    keepalive = { type = "number", default = 60000 },
    producer_request_acks = { type = "number", default = 1, enum = { -1, 0, 1 } },
    producer_request_timeout = { type = "number", default = 2000 },
    producer_request_limits_messages_per_request = { type = "number", default = 200 },
    producer_request_limits_bytes_per_request = { type = "number", default = 1048576 },
    producer_request_retries_max_attempts = { type = "number", default = 10 },
    producer_request_retries_backoff_timeout = { type = "number", default = 100 },
    producer_async = { type = "boolean", default = true },
    producer_async_flush_timeout = { type = "number", default = 1000 },
    producer_async_buffering_limits_messages_in_memory = { type = "number", default = 50000 },
  },
  self_check = regenerate_uuid,
}
