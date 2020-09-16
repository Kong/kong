local statsd_logger = require "kong.plugins.datadog.statsd_logger"


local kong     = kong
local ngx      = ngx
local timer_at = ngx.timer.at
local insert   = table.insert
local gsub     = string.gsub
local pairs    = pairs


local get_consumer_id = {
  consumer_id = function(consumer)
    return consumer and gsub(consumer.id, "-", "_")
  end,
  custom_id = function(consumer)
    return consumer and consumer.custom_id
  end,
  username = function(consumer)
    return consumer and consumer.username
  end
}


local function compose_tags(service_name, status, consumer_id, tags)
  local result = {"name:" ..service_name, "status:"..status}
  if consumer_id ~= nil then
    insert(result, "consumer:" ..consumer_id)
  end
  if tags ~= nil then
    for _, v in pairs(tags) do
      insert(result, v)
    end
  end
  return result
end


local function log(premature, conf, message)
  if premature then
    return
  end

  local name = gsub(message.service.name ~= ngx.null and
                    message.service.name or message.service.host,
                    "%.", "_")

  local stat_name  = {
    request_size     = "request.size",
    response_size    = "response.size",
    latency          = "latency",
    upstream_latency = "upstream_latency",
    kong_latency     = "kong_latency",
    request_count    = "request.count",
  }
  local stat_value = {
    request_size     = message.request and message.request.size,
    response_size    = message.response and message.response.size,
    latency          = message.latencies.request,
    upstream_latency = message.latencies.proxy,
    kong_latency     = message.latencies.kong,
    request_count    = 1,
  }

  local logger, err = statsd_logger:new(conf)
  if err then
    kong.log.err("failed to create Statsd logger: ", err)
    return
  end

  for _, metric_config in pairs(conf.metrics) do
    local stat_name       = stat_name[metric_config.name]
    local stat_value      = stat_value[metric_config.name]
    local get_consumer_id = get_consumer_id[metric_config.consumer_identifier]
    local consumer_id     = get_consumer_id and get_consumer_id(message.consumer) or nil
    local tags            = compose_tags(
            name, message.response and message.response.status or "-",
            consumer_id, metric_config.tags)

    if stat_name ~= nil then
      logger:send_statsd(stat_name, stat_value,
                         logger.stat_types[metric_config.stat_type],
                         metric_config.sample_rate, tags)
    end
  end
  logger:close_socket()
end


local DatadogHandler = {
  PRIORITY = 10,
  VERSION = "3.0.1",
}


function DatadogHandler:log(conf)
  if not ngx.ctx.service then
    return
  end

  local message = kong.log.serialize()
  local ok, err = timer_at(0, log, conf, message)
  if not ok then
    kong.log.err("failed to create timer: ", err)
  end
end


return DatadogHandler
