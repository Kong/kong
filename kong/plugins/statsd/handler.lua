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
  request_size = function (api_name, message, logger)
    local stat = api_name..".request.size"
    logger:gauge(stat, message.request.size, 1)
  end,
  response_size = function (api_name, message, logger)
    local stat = api_name..".response.size"
    logger:gauge(stat, message.response.size, 1)
  end,
  status_count = function (api_name, message, logger)
    local stat = api_name..".request.status."..message.response.status
    logger:counter(stat, 1, 1)
  end,
  latency = function (api_name, message, logger)
    local stat = api_name..".latency"
    logger:gauge(stat, message.latencies.request, 1)
  end,
  request_count = function (api_name, message, logger)
    local stat = api_name..".request.count"
    logger:counter(stat, 1, 1)
  end,
  unique_users = function (api_name, message, logger)
    if message.authenticated_entity ~= nil and message.authenticated_entity.consumer_id ~= nil then
      local stat = api_name..".user.uniques"
      logger:set(stat, message.authenticated_entity.consumer_id)
    end
  end,
  request_per_user = function (api_name, message, logger)
    if message.authenticated_entity ~= nil and message.authenticated_entity.consumer_id ~= nil then
      local stat = api_name.."."..string_gsub(message.authenticated_entity.consumer_id, "-", "_")..".request.count"
      logger:counter(stat, 1, 1)    
    end
  end
}

local function log(premature, conf, message)
  if premature then return end
  
  local logger, err = statsd_logger:new(conf)
  if err then
    ngx_log(NGX_ERR, "failed to create Statsd logger: ", err)
    return
  end
  
  local api_name = string_gsub(message.api.name, "%.", "_")
  for _, metric in pairs(conf.metrics) do
    local gauge = gauges[metric]
    if gauge ~= nil then
      gauge(api_name, message, logger)
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
