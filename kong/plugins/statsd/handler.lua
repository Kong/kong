local statsd_logger = require "kong.plugins.statsd.statsd_logger"


local kong     = kong
local ngx      = ngx
local timer_at = ngx.timer.at
local pairs    = pairs
local gsub     = string.gsub
local fmt      = string.format


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


local metrics = {
  status_count = function (service_name, message, metric_config, logger)
    local response_status = message.response and message.response.status or 0
    local format = fmt("%s.request.status", service_name,
                       response_status)

    logger:send_statsd(fmt("%s.%s", format, response_status),
                       1, logger.stat_types.counter, metric_config.sample_rate)

    logger:send_statsd(fmt("%s.%s", format, "total"), 1,
                       logger.stat_types.counter, metric_config.sample_rate)
  end,
  unique_users = function (service_name, message, metric_config, logger)
    local get_consumer_id = get_consumer_id[metric_config.consumer_identifier]
    local consumer_id     = get_consumer_id(message.consumer)

    if consumer_id then
      local stat = fmt("%s.user.uniques", service_name)

      logger:send_statsd(stat, consumer_id, logger.stat_types.set)
    end
  end,
  request_per_user = function (service_name, message, metric_config, logger)
    local get_consumer_id = get_consumer_id[metric_config.consumer_identifier]
    local consumer_id     = get_consumer_id(message.consumer)

    if consumer_id then
      local stat = fmt("%s.user.%s.request.count", service_name, consumer_id)

      logger:send_statsd(stat, 1, logger.stat_types.counter,
                         metric_config.sample_rate)
    end
  end,
  status_count_per_user = function (service_name, message, metric_config, logger)
    local get_consumer_id = get_consumer_id[metric_config.consumer_identifier]
    local consumer_id     = get_consumer_id(message.consumer)

    if consumer_id then
      local format = fmt("%s.user.%s.request.status", service_name, consumer_id)

      logger:send_statsd(fmt("%s.%s", format, message.response.status),
                         1, logger.stat_types.counter,
                         metric_config.sample_rate)

      logger:send_statsd(fmt("%s.%s", format,  "total"),
                         1, logger.stat_types.counter,
                         metric_config.sample_rate)
    end
  end,
}


local function log(premature, conf, message)
  if premature then
    return
  end

  local name = gsub(message.service.name ~= ngx.null and
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


local StatsdHandler = {
  PRIORITY = 11,
  VERSION = "2.0.1",
}


function StatsdHandler:log(conf)
  if not ngx.ctx.service then
    return
  end

  local message = kong.log.serialize()

  local ok, err = timer_at(0, log, conf, message)
  if not ok then
    kong.log.err("failed to create timer: ", err)
  end
end


return StatsdHandler
