local Queue = require "kong.tools.queue"
local statsd_logger = require "kong.plugins.datadog.statsd_logger"
local kong_meta = require "kong.meta"


local kong     = kong
local ngx      = ngx
local null     = ngx.null
local insert   = table.insert
local gsub     = string.gsub
local pairs    = pairs
local ipairs   = ipairs


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


local function log(conf, messages)
  local logger, err = statsd_logger:new(conf)
  if err then
    kong.log.err("failed to create Statsd logger: ", err)
    return false, err
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
      if stat_name == nil then
        goto continue
      end

      local stat_value      = stat_value[metric_config.name]
      local get_consumer_id = get_consumer_id[metric_config.consumer_identifier]
      local consumer_id     = get_consumer_id and get_consumer_id(message.consumer) or nil
      local tags            = compose_tags(
              name, message.response and message.response.status or "-",
              consumer_id, metric_config.tags, conf)

      logger:send_statsd(stat_name, stat_value,
                         logger.stat_types[metric_config.stat_type],
                         metric_config.sample_rate, tags)
      ::continue::
    end
  end

  logger:close_socket()
  return true
end


local DatadogHandler = {
  PRIORITY = 10,
  VERSION = kong_meta.version,
}


function DatadogHandler:log(conf)
  if not ngx.ctx.service then
    return
  end

  local queue = Queue.get(
    "datadog",
    function(q, entries) return log(q.conf, entries) end,
    Queue.get_params(conf)
  )
  queue.conf = conf

  local message = kong.log.serialize()
  queue:add(message)
end


return DatadogHandler
