local singletons = require "kong.singletons"
local utils = require "kong.tools.utils"
local pl_stringx   = require "pl.stringx"


-- @param value The options string to check for flags (whitespace separated)
-- @param flags List of boolean flags to check for.
-- @returns 1) remainder string after all flags removed, 2) table with flag
-- booleans, 3) sanitized flags string
local function parse_option_flags(value, flags)
  assert(type(value) == "string")

  value = " " .. value .. " "

  local sanitized = ""
  local result = {}

  for _, flag in ipairs(flags) do
    local count
    local patt = "%s" .. flag .. "%s"

    value, count = value:gsub(patt, " ")

    if count > 0 then
      result[flag] = true
      sanitized = sanitized .. " " .. flag

    else
      result[flag] = false
    end
  end

  return pl_stringx.strip(value), result, pl_stringx.strip(sanitized)
end


local function new()
  local conf = singletons.configuration
  -- skip creating internal statsd plugin if not using prometheus strategy
  -- or vitals is not enabled
  if conf.vitals_strategy ~= "prometheus" or not singletons.configuration.vitals then
    return true, nil
  end

  -- this will not raise if statsd-advanced is configured in custom_plugins but is not exist
  local ok, _ = utils.load_module_if_exists("kong.plugins.statsd-advanced.handler")
  if not ok then
    return false, "trying to enable internal statsd-advanced plugin but it is not installed"
  end

  ngx.log(ngx.DEBUG, "enabling internal statsd-advanced plugin")

  local host, port, use_tcp
  local remainder, _, protocol = parse_option_flags(conf.vitals_statsd_address, { "udp", "tcp" })
  if remainder then
    host, port = remainder:match("(.+):([%d]+)$")
    port = tonumber(port)
    if not host or not port then
      host = remainder:match("(unix:/.+)$")
      port = nil
    end
  end
  use_tcp = protocol == "tcp"

  singletons.internal_proxies:add_plugin({
    name = "statsd-advanced",
    config = {
      host = host,
      port = port,
      prefix = conf.vitals_statsd_prefix,
      use_tcp = use_tcp,
      udp_packet_size = conf.vitals_statsd_udp_packet_size or 0,
      metrics = {
        { name = "request_count", sample_rate = 1, stat_type = "counter", service_identifier = "service_id" },
        { name = "status_count", sample_rate = 1, stat_type = "counter", service_identifier = "service_id" },
        { name = "upstream_latency", stat_type = "timer", service_identifier = "service_id" },
        { name = "kong_latency", stat_type = "timer", service_identifier = "service_id" },
        { name = "status_count_per_user", sample_rate = 1, consumer_identifier = "consumer_id",
          stat_type = "counter", service_identifier = "service_id" },
        { name = "status_count_per_user_per_route", sample_rate = 1, consumer_identifier = "consumer_id",
          stat_type = "counter", service_identifier = "service_id" },
        { name = "cache_datastore_misses_total", sample_rate = 1, stat_type = "counter",
          service_identifier = "service_id" },
        { name = "cache_datastore_hits_total", sample_rate = 1, stat_type = "counter",
          service_identifier = "service_id" },
        { name = "shdict_usage", sample_rate = 1, stat_type = "gauge", service_identifier = "service_id" },
      },
    }
  })

  return true, nil
end

return {
  new = new
}
