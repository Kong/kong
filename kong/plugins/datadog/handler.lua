local BatchQueue = require "kong.tools.batch_queue"
local statsd_logger = require "kong.plugins.datadog.statsd_logger"
local kong_meta = require "kong.meta"


local kong     = kong
local ngx      = ngx
local null     = ngx.null
local insert   = table.insert
local gsub     = string.gsub
local pairs    = pairs
local ipairs   = ipairs
local fmt      = string.format
local concat   = table.concat


local queues = {}


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


local function compose_tags(service_name, status, consumer_id, tags, conf)
  local result = {
    (conf.service_name_tag or "name") .. ":" .. service_name,
    (conf.status_tag or "status") .. ":" .. status
  }

  if consumer_id ~= nil then
    insert(result, (conf.consumer_tag or "consumer") .. ":" .. consumer_id)
  end

  if tags ~= nil then
    for _, v in pairs(tags) do
      insert(result, v)
    end
  end

  return result
end


local function get_queue_id(conf)
  local queue_id = fmt("%s:%s:%s:%s:%s:%s",
                       conf.host,
                       conf.port,
                       conf.prefix,
                       conf.service_name_tag,
                       conf.status_tag,
                       conf.consumer_tag)

  for _, metric_config in ipairs(conf.metrics) do
    if metric_config ~= nil then
      local tags_id = metric_config.tags and concat(metric_config.tags, ":") or ""
      local metric_config_id = fmt("%s:%s:%s:%s:%s",
                                   metric_config.name,
                                   metric_config.stat_type,
                                   tags_id,
                                   metric_config.sample_rate,
                                   metric_config.consumer_identifier)
      queue_id = queue_id .. ":" .. metric_config_id
    end
  end

  return queue_id
end


local function log(conf, messages)
  local logger, err = statsd_logger:new(conf)
  if err then
    kong.log.err("failed to create Statsd logger: ", err)
    return
  end

  for _, message in ipairs(messages) do
    local name = gsub(message.service.name ~= null and
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

    for _, metric_config in pairs(conf.metrics) do
      local stat_name       = stat_name[metric_config.name]
      local stat_value      = stat_value[metric_config.name]
      local get_consumer_id = get_consumer_id[metric_config.consumer_identifier]
      local consumer_id     = get_consumer_id and get_consumer_id(message.consumer) or nil
      local tags            = compose_tags(
              name, message.response and message.response.status or "-",
              consumer_id, metric_config.tags, conf)

      if stat_name ~= nil then
        logger:send_statsd(stat_name, stat_value,
                           logger.stat_types[metric_config.stat_type],
                           metric_config.sample_rate, tags)
      end
    end
  end

  logger:close_socket()
end


local DatadogHandler = {
  PRIORITY = 10,
  VERSION = kong_meta.version,
}


function DatadogHandler:log(conf)
  if not ngx.ctx.service then
    return
  end

  local queue_id = get_queue_id(conf)
  local q = queues[queue_id]
  if not q then
    local batch_max_size = conf.queue_size or 1
    local process = function (entries)
      return log(conf, entries)
    end

    local opts = {
      retry_count    = conf.retry_count or 10,
      flush_timeout  = conf.flush_timeout or 2,
      batch_max_size = batch_max_size,
      process_delay  = 0,
    }

    local err
    q, err = BatchQueue.new(process, opts)
    if not q then
      kong.log.err("could not create queue: ", err)
      return
    end
    queues[queue_id] = q
  end

  local message = kong.log.serialize()
  q:add(message)
end


return DatadogHandler
