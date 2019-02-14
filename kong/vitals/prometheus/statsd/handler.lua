local basic_serializer = require "kong.plugins.log-serializers.basic"
local statsd_logger    = require "kong.vitals.prometheus.statsd.logger"
local utils            = require "kong.tools.utils"
local vitals           = require "kong.vitals"


local ngx_log       = ngx.log
local ngx_timer_at  = ngx.timer.at
local ngx_time      = ngx.time
local re_gsub       = ngx.re.gsub
local pairs         = pairs
local string_format = string.format
local NGX_ERR       = ngx.ERR
local ee_metrics    = vitals.logging_metrics or {}


local _M = {}

local worker_id
local hostname = re_gsub(utils.get_hostname(), [[\.]], "_", "oj")

-- downsample timestamp
local shdict_metrics_last_sent = 0
local SHDICT_METRICS_SEND_THRESHOLD = 60


local get_consumer_id = {
  consumer_id = function(consumer)
    return consumer and consumer.id
  end,
  custom_id   = function(consumer)
    return consumer and consumer.custom_id
  end,
  username    = function(consumer)
    return consumer and consumer.username
  end
}

local get_service_id = {
  service_id           = function(service)
    return service and service.id
  end,
  service_name         = function(service)
    return service and service.name
  end,
  service_host         = function(service)
    return service and service.host
  end,
  service_name_or_host = function(service)
    return service and (service.name ~= ngx.null and
                                   service.name or service.host)
  end
}

local get_workspace_id = {
  workspace_id         = function(workspaces)
    return workspaces and workspaces[1] and workspaces[1].id
  end,
  workspace_name       = function(workspaces)
    return workspaces and workspaces[1] and workspaces[1].name
  end
}

local metrics = {   
  unique_users = function (scope_name, message, metric_config, logger)
    local get_consumer_id = get_consumer_id[metric_config.consumer_identifier]
    local consumer_id     = get_consumer_id(message.consumer)

    if consumer_id then
      local stat = string_format("%s.user.uniques", scope_name)
      logger:send_statsd(stat, consumer_id, logger.stat_types.set)
    end
  end,
  request_per_user = function (scope_name, message, metric_config, logger)
    local get_consumer_id = get_consumer_id[metric_config.consumer_identifier]
    local consumer_id     = get_consumer_id(message.consumer)

    if consumer_id then
      local stat = string_format("%s.user.%s.request.count", scope_name, consumer_id)
      logger:send_statsd(stat, 1, logger.stat_types.counter,
                         metric_config.sample_rate)
    end
  end,
  status_count = function (scope_name, message, metric_config, logger)
    logger:send_statsd(string_format("%s.status.%s", scope_name, message.response.status),
                       1, logger.stat_types.counter, metric_config.sample_rate)
  end,
  status_count_per_user = function (scope_name, message, metric_config, logger)
    local get_consumer_id = get_consumer_id[metric_config.consumer_identifier]
    local consumer_id     = get_consumer_id(message.consumer)

    if consumer_id then
      logger:send_statsd(string_format("%s.user.%s.status.%s", scope_name,
                                       consumer_id, message.response.status),
                         1, logger.stat_types.counter,
                         metric_config.sample_rate)
    end
  end,
  status_count_per_workspace = function (scope_name, message, metric_config, logger)
    local get_workspace_id = get_workspace_id[metric_config.workspace_identifier]
    local workspace_id     = get_workspace_id(message.workspaces)

    if workspace_id then
      logger:send_statsd(string_format("%s.workspace.%s.status.%s", scope_name,
                                       workspace_id, message.response.status),
                         1, logger.stat_types.counter,
                         metric_config.sample_rate)
    end
  end,
  status_count_per_user_per_route = function (_, message, metric_config, logger)
    local get_consumer_id = get_consumer_id[metric_config.consumer_identifier]
    local consumer_id     = get_consumer_id(message.consumer)
    if not consumer_id then
      return
    end

    local route = message.route

    if route.id then
      logger:send_statsd(string_format("route.%s.user.%s.status.%s", route.id,
                                       consumer_id, message.response.status),
                         1, logger.stat_types.counter,
                         metric_config.sample_rate)
    end
  end,
}

-- add vitals metrics
for group_name, group in pairs(ee_metrics) do
  for metric, metric_type in pairs(group) do
    -- add handler to metrics table
    metrics[metric] = function(scope_name, message, metric_config, logger)
      local value = (message[group_name] or {})[metric]
      -- only send metrics when the value is not nil
      if value ~= nil then
        logger:send_statsd(string_format("%s.%s", scope_name, metric),
                           value, logger.stat_types[metric_type],
                           metric_config.sample_rate)
      end
    end
  end
end

-- add shdict metrics
if ngx.config.ngx_lua_version >= 10011 then
  metrics.shdict_usage = function (_, message, metric_config, logger)
    -- we don't need this for every request, send every 1 minute
    -- also only one worker needs to send this because it's shared
    if worker_id == 0 then
      local now = ngx_time()
      if shdict_metrics_last_sent + SHDICT_METRICS_SEND_THRESHOLD < now then
        shdict_metrics_last_sent = now
        for shdict_name, shdict in pairs(ngx.shared) do
          logger:send_statsd(string_format("node.%s.shdict.%s.free_space",
                                           hostname, shdict_name),
                             shdict:free_space(), logger.stat_types.gauge,
                             metric_config.sample_rate)
          logger:send_statsd(string_format("node.%s.shdict.%s.capacity",
                                           hostname, shdict_name),
                             shdict:capacity(), logger.stat_types.gauge,
                             metric_config.sample_rate)
        end
      end
    end
  end
end

local function get_scope_name(message, service_identifier)
  local api = message.api
  local service = message.service

  if service then
     -- don't fail on ce schema where service_identifier is not defined
    if not service_identifier then
      service_identifier = "service_name_or_host"
    end
    local service_name = get_service_id[service_identifier](service)
    if service_name == ngx.null then
      return "service.unnamed"
    end
    return "service." .. re_gsub(service_name, [[\.]], "_", "oj")

  elseif api then
    if api == ngx.null then
      return "api.unnamed"
    end
    return "api." .. re_gsub(api.name, [[\.]], "_", "oj")

  else
    -- TODO: this follows the pattern used by
    -- https://github.com/Kong/kong/pull/2702 (which prevents an error from
    -- being thrown and avoids confusing reports as per our metrics keys), but
    -- as it stands, hides traffic from monitoring tools when the plugin is
    -- configured globally. In fact, this basically disables this plugin when
    -- it is configured to run globally, or per-consumer without an
    -- API/Route/Service.
    
    -- Changes in statsd-advanced: we still log these requests, but into a namespace of
    -- "global.unmatched".
    -- And we don't send upstream_latency and metrics with consumer or route
    return "global.unmatched"
  end
end

local function log(premature, conf, message)
  if premature then
    return
  end

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
    ngx_log(NGX_ERR, "[statsd.handler] failed to create Statsd logger: ", err)
    return
  end

  for _, metric_config in pairs(conf.metrics) do
    local metric_config_name = metric_config.name
    local metric = metrics[metric_config_name]

    local name = get_scope_name(message, metric_config.service_identifier)

    if metric then
      metric(name, message, metric_config, logger)

    else
      local stat_name = stat_name[metric_config_name]
      local stat_value = stat_value[metric_config_name]

      if stat_value ~= nil and stat_value ~= -1 then
        logger:send_statsd(name .. "." .. stat_name, stat_value,
                           logger.stat_types[metric_config.stat_type],
                           metric_config.sample_rate)
      end
    end
  end

  logger:close_socket()
end

function _M.new(static_config)
  return setmetatable({
    static_config = static_config
  }, { __index = _M })
end

function _M:log(conf)
  conf = conf or self.static_config
  -- TODO: cache worker id in module local variable
  worker_id = ngx.worker.id()

  local message = basic_serializer.serialize(ngx)
  local ngx_ctx = ngx.ctx
  for group_name, group in pairs(ee_metrics) do
    message[group_name] = ngx_ctx[group_name]
  end

  conf._prefix = conf.prefix

  if conf.hostname_in_prefix then
    conf._prefix = conf._prefix .. ".node." .. hostname
  end

  local ok, err = ngx_timer_at(0, log, conf, message)
  if not ok then
    ngx_log(NGX_ERR, "[statsd.handler] failed to create timer: ", err)
  end
end


return _M
