-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]
local kong = kong
local kafka_producer = require "resty.kafka.producer"

local mt_cache = { __mode = "k" }
local producers_cache = setmetatable({}, mt_cache)


local function is_auth_enabled(config)
  return config.strategy and config.mechanism
end

--- Creates a new Kafka Producer.
local function create(conf)
  local broker_list = conf.bootstrap_servers

  local producer_config = {
    -- settings affecting all Kafka APIs (including Metadata API, Produce API, etc)
    socket_timeout = conf.timeout,
    keepalive_timeout = conf.keepalive,
    keepalive = conf.keepalive_enabled,

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

    ssl = conf.security.ssl,
  }
  local cluster_name = conf.cluster_name

  if not cluster_name then
    kong.log.warn("no cluster_name provided in plugin configuration, using default cluster name. If more than one Kafka plugin " ..
      "is configured without a cluster_name, these plugins will use the same cluster")
  end

  -- set auth config if it is enabled
  if is_auth_enabled(conf.authentication) then
    kong.log.debug("enabling authentication: " .. tostring(conf.authentication.strategy)  .. "/" .. tostring(conf.authentication.mechanism))

    producer_config.auth_config = {
      strategy = conf.authentication.strategy,
      mechanism = conf.authentication.mechanism,
      user = conf.authentication.user,
      password = conf.authentication.password,
      tokenauth = conf.authentication.tokenauth,
    }
  end

  -- set certificates for mTLS authentication
  if conf.security.ssl and conf.security.client_cert and conf.security.client_priv_key then
    kong.log.debug("enabling mTLS configuration")

    producer_config.client_cert = conf.security.client_cert
    producer_config.client_priv_key = conf.security.client_priv_key
  end

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
