local BasePlugin = require "kong.plugins.base_plugin"
local basic_serializer = require "kong.plugins.log-serializers.basic"
local statsd_logger = require "kong.plugins.statsd.statsd_logger"

local StatsdHandler = BasePlugin:extend()

StatsdHandler.PRIORITY = 1

local ngx_log = ngx.log
local ngx_timer_at = ngx.timer.at
local string_gsub = string.gsub
local pairs = pairs
local NGX_ERR = ngx.ERR

local gauges = {
  gauge = function (stat_name, stat_value, metric_config, logger)
    local sample_rate = metric_config.sample_rate
    logger:stat_type(stat_name, stat_value, sample_rate)
  end,
  timer = function (stat_name, stat_value, metric_config, logger)
    logger:timer(stat_name, stat_value)
  end,
  counter = function (stat_name, stat_value, metric_config, logger)
    local sample_rate = metric_config.sample_rate
    logger:counter(stat_name, 1, sample_rate)
  end,
  set = function (stat_name, stat_value, metric_config, logger)
    logger:set(stat_name, stat_value)
  end,
  histogram = function (stat_name, stat_value, metric_config, logger)
    logger:histogram(stat_name, stat_value)
  end,
  meter = function (stat_name, stat_value, metric_config, logger)
    logger:meter(stat_name, stat_value)
  end,
  status_count = function (api_name, message, metric_config, logger)
    local stat = api_name..".request.status."..message.response.status
    local total_count = api_name..".request.status.total"
    local sample_rate = metric_config.sample_rate
    logger:counter(stat, 1, sample_rate)
    logger:counter(total_count, 1, sample_rate)
  end,
  unique_users = function (api_name, message, metric_config, logger)
    local identifier = metric_config.consumer_identifier
    if message.authenticated_entity ~= nil and message.authenticated_entity[identifier] ~= nil then
      local stat = api_name..".user.uniques"
      logger:set(stat, message.authenticated_entity[identifier])
    end
  end,
  request_per_user = function (api_name, message, metric_config, logger)
    local identifier = metric_config.consumer_identifier
    if message.authenticated_entity ~= nil and message.authenticated_entity[identifier] ~= nil then
      local sample_rate = metric_config.sample_rate
      local stat = api_name..".user."..string_gsub(message.authenticated_entity[identifier], "-", "_")..".request.count"
      logger:counter(stat, 1, sample_rate)
    end
  end,
  status_count_per_user = function (api_name, message, metric_config, logger)
    local identifier = metric_config.consumer_identifier
    if message.authenticated_entity ~= nil and message.authenticated_entity[identifier] ~= nil then
      local stat = api_name..".user."..string_gsub(message.authenticated_entity[identifier], "-", "_")..".request.status."..message.response.status
      local total_count = api_name..".user."..string_gsub(message.authenticated_entity[identifier], "-", "_")..".request.status.total"
      local sample_rate = metric_config.sample_rate
      logger:counter(stat, 1, sample_rate)
      logger:counter(total_count, 1, sample_rate)
    end
  end
}

local function log(premature, conf, message)
  if premature then return end

  local api_name = string_gsub(message.api.name, "%.", "_")

  local stat_name = {
    request_size = api_name..".request.size",
    response_size = api_name..".response.size",
    latency = api_name..".latency",
    upstream_latency = api_name..".upstream_latency",
    kong_latency = api_name..".kong_latency",
    request_count = api_name..".request.count"
  }

  local stat_value = {
    request_size = message.request.size,
    response_size = message.response.size,
    latency = message.latencies.request,
    upstream_latency = message.latencies.proxy,
    kong_latency = message.latencies.kong,
    request_count = api_name..".request.count"
  }

  local logger, err = statsd_logger:new(conf)

  if err then
    ngx_log(NGX_ERR, "failed to create Statsd logger: ", err)
    return
  end

  for _, metric_config in pairs(conf.metrics) do
    if metric_config.name ~= "status_count" and metric_config.name ~= "unique_users" and metric_config.name ~= "request_per_user" and metric_config.name ~= "status_count_per_user" then
      local stat_name = stat_name[metric_config.name]
      local stat_value = stat_value[metric_config.name]
      local gauge = gauges[metric_config.stat_type]
      if stat_name ~= nil and gauge ~= nil and stat_value ~= nil then
        gauge(stat_name, stat_value, metric_config, logger)
      end
    else
      local gauge = gauges[metric_config.name]
      if gauge ~= nil then
        gauge(api_name, message, metric_config, logger)
      end
    end
  end

  logger:close_socket()
end

function StatsdHandler:new()
  StatsdHandler.super.new(self, "statsd")
end

function StatsdHandler:log(conf)
  StatsdHandler.super.log(self)
  local message = basic_serializer.serialize(ngx)

  local ok, err = ngx_timer_at(0, log, conf, message)
  if not ok then
    ngx_log(NGX_ERR, "failed to create timer: ", err)
  end
end

return StatsdHandler
