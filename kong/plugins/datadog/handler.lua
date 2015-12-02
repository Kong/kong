local BasePlugin = require "kong.plugins.base_plugin"
local basic_serializer = require "kong.plugins.log-serializers.basic"
local statsd_logger = require "kong.plugins.datadog.statsd_logger"

local ngx_log = ngx.log
local ngx_timer_at = ngx.timer.at
local string_gsub = string.gsub
local pairs = pairs
local NGX_ERR = ngx.ERR

local function request_counter(api_name, logger)
  local stat = api_name..".request.count"
  logger:counter(stat, 1, 1)
end

local function status_counter(api_name, message, logger)
  local stat = api_name..".request.status."..message.response.status
  logger:counter(stat, 1, 1)
end

local function request_size_gauge(api_name, message, logger)
  local stat = api_name..".request.size"
  logger:gauge(stat, message.request.size, 1)
end

local function latency_gauge(api_name, message, logger)
  local stat = api_name..".latency"
  logger:gauge(stat, message.latencies.request, 1)
end

local function log(premature, conf, message)
  if premature then return end
  
  local logger, err = statsd_logger:new(conf)
  if err then
    ngx_log(NGX_ERR, "failed to create Statsd logger: ", err)
    return
  end
  
  local api_name = string_gsub(message.api.name, "%.", "_")
  for _, metric in pairs(conf.metrics) do
    if metric == "request_size" then
      request_size_gauge(api_name, message, logger)
    end
    if metric == "status_count" then
      status_counter(api_name, message, logger)
    end
    if metric == "latency" then
      latency_gauge(api_name, message, logger)
    end
    if metric == "request_count" then
      request_counter(api_name, logger)
    end
  end
 
  logger:close_socket()
end

local DatadogHandler = BasePlugin:extend()

function DatadogHandler:new()
  DatadogHandler.super.new(self, "datadog")
end

function DatadogHandler:log(conf)
  DatadogHandler.super.log(self)
  local message = basic_serializer.serialize(ngx)
  
  local ok, err = ngx_timer_at(0, log, conf, message)
  if not ok then
    ngx_log(NGX_ERR, "failed to create timer: ", err)
  end
end

DatadogHandler.PRIORITY = 1

return DatadogHandler
