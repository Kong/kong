local singletons = require "kong.singletons"
local utils = require "kong.tools.utils"


local function new()
  local conf = singletons.configuration
  -- skip creating internal statsd plugin if using vitals postgres/cassandra strategy
  -- or vitals is not enabled
  if conf.vitals_strategy == "database" or not singletons.configuration.vitals then
    return true, nil
  end

  -- this will not raise if statsd-advanced is configured in custom_plugins but is not exist
  local ok, _ = utils.load_module_if_exists("kong.plugins.statsd-advanced.handler")
  if not ok then
    return false, "trying to enable internal statsd-advanced plugin but it is not installed"
  end

  ngx.log(ngx.DEBUG, "enabling internal statsd-advanced plugin")

  singletons.internal_proxies:add_plugin({
    name = "statsd-advanced",
    config = {
      host = conf.vitals_statsd_host,
      port = conf.vitals_statsd_port,
      prefix = conf.vitals_statsd_prefix,
      use_tcp = conf.vitals_statsd_use_tcp,
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
