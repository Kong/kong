local kafka_producer = require "resty.kafka.producer"

local mt_cache = { __mode = "k" }
local producers_cache = setmetatable({}, mt_cache)

--- Creates a new Kafka Producer.
local function create(conf)
  local broker_list = conf.bootstrap_servers
  local producer_config = {
    -- settings affecting all Kafka APIs (including Metadata API, Produce API, etc)
    socket_timeout = conf.timeout,
    keepalive_timeout = conf.keepalive,

    -- settings specific to Kafka Produce API
    required_acks = conf.producer_request_acks,
    request_timeout = conf.producer_request_timeout,

    batch_num = conf.producer_request_limits_messages_per_request,
    batch_size = conf.producer_request_limits_bytes_per_request,

    max_retry = conf.producer_request_retries_max_attempts,
    retry_backoff = conf.producer_request_retries_backoff_timeout,

    producer_type = conf.producer_async and "async" or "sync",
    flush_time = conf.producer_async_flush_timeout,
    max_buffering = conf.producer_async_buffering_limits_messages_in_memory,
  }
  local cluster_name = conf.uuid

  return kafka_producer:new(broker_list, producer_config, cluster_name)
end


local function get_or_create(conf)
  local producer = producers_cache[conf]
  if producer then
    return producer
  end
  kong.log.notice("creating a new Kafka Producer for configuration table: ", tostring(conf))

  local err
  producer, err = create(conf)
  if not producer then
    return nil, err
  end

  producers_cache[conf] = producer

  return producer
end


return { get_or_create = get_or_create }
