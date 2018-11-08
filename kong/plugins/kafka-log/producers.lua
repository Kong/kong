local kafka_producer = require "resty.kafka.producer"
local types = require "kong.plugins.kafka-log.types"
local ipairs = ipairs

--- Creates a new Kafka Producer.
local function create_producer(conf)
  local broker_list = {}
  for idx, value in ipairs(conf.bootstrap_servers) do
    local server = types.bootstrap_server(value)
    if not server then
      return nil, "invalid bootstrap server value: " .. value
    end
    broker_list[idx] = server
  end

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

return { new = create_producer }
