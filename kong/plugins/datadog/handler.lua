local BasePlugin       = require "kong.plugins.base_plugin"
local basic_serializer = require "kong.plugins.log-serializers.basic"
local statsd_logger    = require "kong.plugins.datadog.statsd_logger"


local ngx_log       = ngx.log
local ngx_timer_at  = ngx.timer.at
local string_gsub   = string.gsub
local pairs         = pairs
local string_format = string.format
local NGX_ERR       = ngx.ERR


local DatadogHandler    = BasePlugin:extend()
DatadogHandler.PRIORITY = 10
DatadogHandler.VERSION = "0.1.0"


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
  status_count = function (api_name, message, metric_config, logger)
    local fmt = string_format("%s.request.status", api_name,
                       message.response.status)

    logger:send_statsd(string_format("%s.%s", fmt, message.response.status),
                       1, logger.stat_types.counter,
                       metric_config.sample_rate, metric_config.tags)

    logger:send_statsd(string_format("%s.%s", fmt, "total"), 1,
                       logger.stat_types.counter,
                       metric_config.sample_rate, metric_config.tags)
  end,
  unique_users = function (api_name, message, metric_config, logger)
    local get_consumer_id = get_consumer_id[metric_config.consumer_identifier]
    local consumer_id     = get_consumer_id(message.consumer)

    if consumer_id then
      local stat = string_format("%s.user.uniques", api_name)

      logger:send_statsd(stat, consumer_id, logger.stat_types.set,
                         nil, metric_config.tags)
    end
  end,
  request_per_user = function (api_name, message, metric_config, logger)
    local get_consumer_id = get_consumer_id[metric_config.consumer_identifier]
    local consumer_id     = get_consumer_id(message.consumer)

    if consumer_id then
      local stat = string_format("%s.user.%s.request.count", api_name, consumer_id)

      logger:send_statsd(stat, 1, logger.stat_types.counter,
                         metric_config.sample_rate, metric_config.tags)
    end
  end,
  status_count_per_user = function (api_name, message, metric_config, logger)
    local get_consumer_id = get_consumer_id[metric_config.consumer_identifier]
    local consumer_id     = get_consumer_id(message.consumer)

    if consumer_id then
      local fmt = string_format("%s.user.%s.request.status", api_name, consumer_id)

      logger:send_statsd(string_format("%s.%s", fmt, message.response.status),
                         1, logger.stat_types.counter,
                         metric_config.sample_rate, metric_config.tags)

      logger:send_statsd(string_format("%s.%s", fmt,  "total"),
                         1, logger.stat_types.counter,
                         metric_config.sample_rate, metric_config.tags)
    end
  end,
}


local function log(premature, conf, message)
  if premature then
    return
  end

  local name

  if message.service and message.service.name then
    name = string_gsub(message.service.name ~= ngx.null and
                       message.service.name or message.service.host,
                       "%.", "_")

  elseif message.api and message.api.name then
    name = string_gsub(message.api.name, "%.", "_")

  else
    -- TODO: this follows the pattern used by
    -- https://github.com/Kong/kong/pull/2702 (which prevents an error from
    -- being thrown and avoids confusing reports as per our metrics keys), but
    -- as it stands, hides traffic from monitoring tools when the plugin is
    -- configured globally. In fact, this basically disables this plugin when
    -- it is configured to run globally, or per-consumer without an
    -- API/Route/Service.
    ngx_log(ngx.DEBUG,
            "[statsd] no Route/Service/API in context, skipping logging")
    return
  end

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
      local stat_name  = stat_name[metric_config.name]
      local stat_value = stat_value[metric_config.name]

      logger:send_statsd(stat_name, stat_value,
                         logger.stat_types[metric_config.stat_type],
                         metric_config.sample_rate, metric_config.tags)
    end
  end

  logger:close_socket()
end


function DatadogHandler:new()
  DatadogHandler.super.new(self, "datadog")
end

function DatadogHandler:log(conf)
  DatadogHandler.super.log(self)

  local routing = ngx.ctx.proxy_request_state.routing
  if not routing.service and
     not routing.api     then
    return
  end

  local message = basic_serializer.serialize(ngx)

  local ok, err = ngx_timer_at(0, log, conf, message)
  if not ok then
    ngx_log(NGX_ERR, "failed to create timer: ", err)
  end
end

return DatadogHandler
