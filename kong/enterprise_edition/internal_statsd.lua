local singletons = require "kong.singletons"
local feature_flags = require "kong.enterprise_edition.feature_flags"
local utils = require "kong.tools.utils"
local cjson = require("cjson.safe")
local FF_FLAGS = feature_flags.FLAGS
local FF_VALUES = feature_flags.VALUES


local function new()
  if not feature_flags.is_enabled(FF_FLAGS.INTERNAL_STATSD_PLUGIN) then
    return true, nil
  end

  local statsd_config_str, _ = feature_flags.get_feature_value(FF_VALUES.INTERNAL_STATSD_PLUGIN_CONFIG)
  if not statsd_config_str then
    return false, "internal statsd is enabled but statsd-advanced configuration is not defined"
  end

  if not singletons.internal_proxies then
    return false, "internal proxies is not initalized, skip adding internal statsd plugin"
  end
  
  if type(statsd_config_str) == "table" then
    statsd_config_str = table.concat(statsd_config_str, ",")
  end

  local statsd_config, err = cjson.decode(statsd_config_str)
  if not statsd_config then
    return false,
      string.format("\"%s\" is not valid JSON for internal statsd-advanced config: %s", statsd_config_str, err)
  end

  -- this will not raise if statsd-advanced is configured in custom_plugins but is not exist
  local ok, _ = utils.load_module_if_exists("kong.plugins.statsd-advanced.handler")
  if not ok then
    return false, "trying to enable internal statsd-advanced plugin but it is not installed"
  end

  ngx.log(ngx.DEBUG, "enabling internal statsd-advanced plugin: ", statsd_config_str)

  singletons.internal_proxies:add_plugin({
    name = "statsd-advanced",
    config = {
      host = statsd_config.host,
      port = tonumber(statsd_config.port),
      prefix = statsd_config.prefix,
      use_tcp = statsd_config.use_tcp,
      udp_packet_size = statsd_config.udp_packet_size or 0,
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
