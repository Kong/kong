local basic_serializer = require "kong.plugins.log-serializers.basic"
local statsd_logger    = require "kong.plugins.statsd.statsd_logger"


local ngx_log       = ngx.log
local ngx_timer_at  = ngx.timer.at
local string_gsub   = string.gsub
local pairs         = pairs
local string_format = string.format
local NGX_ERR       = ngx.ERR


local StatsdHandler = {}
StatsdHandler.PRIORITY = 11
StatsdHandler.VERSION = "2.0.0"


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


local metrics = {
  status_count = function (service_name, message, metric_config, logger)
    local fmt = string_format("%s.request.status", service_name,
                       message.response.status)

    logger:send_statsd(string_format("%s.%s", fmt, message.response.status),
                       1, logger.stat_types.counter, metric_config.sample_rate)

    logger:send_statsd(string_format("%s.%s", fmt, "total"), 1,
                       logger.stat_types.counter, metric_config.sample_rate)
  end,
  unique_users = function (service_name, message, metric_config, logger)
    local get_consumer_id = get_consumer_id[metric_config.consumer_identifier]
    local consumer_id     = get_consumer_id(message.consumer)

    if consumer_id then
      local stat = string_format("%s.user.uniques", service_name)

      logger:send_statsd(stat, consumer_id, logger.stat_types.set)
    end
  end,
  request_per_user = function (service_name, message, metric_config, logger)
    local get_consumer_id = get_consumer_id[metric_config.consumer_identifier]
    local consumer_id     = get_consumer_id(message.consumer)

    if consumer_id then
      local stat = string_format("%s.user.%s.request.count", service_name, consumer_id)

      logger:send_statsd(stat, 1, logger.stat_types.counter,
                         metric_config.sample_rate)
    end
  end,
  status_count_per_user = function (service_name, message, metric_config, logger)
    local get_consumer_id = get_consumer_id[metric_config.consumer_identifier]
    local consumer_id     = get_consumer_id(message.consumer)

    if consumer_id then
      local fmt = string_format("%s.user.%s.request.status", service_name, consumer_id)

      logger:send_statsd(string_format("%s.%s", fmt, message.response.status),
                         1, logger.stat_types.counter,
                         metric_config.sample_rate)

      logger:send_statsd(string_format("%s.%s", fmt,  "total"),
                         1, logger.stat_types.counter,
                         metric_config.sample_rate)
    end
  end,
}


local function log(premature, conf, message)
  if premature then
    return
  end

  local name = string_gsub(message.service.name ~= ngx.null and
                           message.service.name or message.service.host,
                           "%.", "_")

  local stat_name  = {
    request_size     = name .. ".request.size",
    response_size    = name .. ".response.size",
    latency          = name .. ".latency",
    upstream_latency = name .. ".upstream_latency",
    kong_latency     = name .. ".kong_latency",
    request_count    = name .. ".request.count",
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
    local metric = metrics[metric_config.name]

    if metric then
      metric(name, message, metric_config, logger)

    else
      local stat_name = stat_name[metric_config.name]
      local stat_value = stat_value[metric_config.name]

      logger:send_statsd(stat_name, stat_value,
                         logger.stat_types[metric_config.stat_type],
                         metric_config.sample_rate)
    end
  end

  logger:close_socket()
end


function StatsdHandler:log(conf)
  if not ngx.ctx.service then
    return
  end

  local message = basic_serializer.serialize(ngx)

  local ok, err = ngx_timer_at(0, log, conf, message)
  if not ok then
    ngx_log(NGX_ERR, "failed to create timer: ", err)
  end
end


return StatsdHandler
