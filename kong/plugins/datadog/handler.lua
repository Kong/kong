local basic_serializer = require "kong.plugins.log-serializers.basic"
local statsd_logger    = require "kong.plugins.datadog.statsd_logger"


local ngx_log       = ngx.log
local ngx_timer_at  = ngx.timer.at
local string_gsub   = string.gsub
local pairs         = pairs
local NGX_ERR       = ngx.ERR


local DatadogHandler    = {}
DatadogHandler.PRIORITY = 10
DatadogHandler.VERSION = "3.0.0"


local get_consumer_id = {
  consumer_id = function(consumer)
    return consumer and string_gsub(consumer.id, "-", "_")
  end,
  custom_id   = function(consumer)
    return consumer and consumer.custom_id
  end,
  username    = function(consumer)
    return consumer and consumer.username
  end
}


local function compose_tags(service_name, status, consumer_id, tags)
  local result = {"name:" ..service_name, "status:"..status}
  if consumer_id ~= nil then
    table.insert(result, "consumer:" ..consumer_id)
  end
  if tags ~= nil then
    for _, v in pairs(tags) do
      table.insert(result, v)
    end
  end
  return result
end


local function log(premature, conf, message)
  if premature then
    return
  end

  local name = string_gsub(message.service.name ~= ngx.null and
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
    request_size     = message.request.size,
    response_size    = message.response.size,
    latency          = message.latencies.request,
    upstream_latency = message.latencies.proxy,
    kong_latency     = message.latencies.kong,
    request_count    = 1,
  }

  local logger, err = statsd_logger:new(conf)
  if err then
    ngx_log(NGX_ERR, "failed to create Statsd logger: ", err)
    return
  end

  for _, metric_config in pairs(conf.metrics) do
    local stat_name       = stat_name[metric_config.name]
    local stat_value      = stat_value[metric_config.name]
    local get_consumer_id = get_consumer_id[metric_config.consumer_identifier]
    local consumer_id     = get_consumer_id and get_consumer_id(message.consumer) or nil
    local tags            = compose_tags(name, message.response.status, consumer_id, metric_config.tags)

    if stat_name ~= nil then
      logger:send_statsd(stat_name, stat_value,
                         logger.stat_types[metric_config.stat_type],
                         metric_config.sample_rate, tags)
    end
  end
  logger:close_socket()
end


function DatadogHandler:log(conf)
  if not ngx.ctx.service then
    return
  end

  local message = basic_serializer.serialize(ngx)

  local ok, err = ngx_timer_at(0, log, conf, message)
  if not ok then
    ngx_log(NGX_ERR, "failed to create timer: ", err)
  end
end

return DatadogHandler
