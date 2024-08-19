-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]
local kong = kong
local kafka_producer = require "resty.kafka.producer"
local cert_utils = require "kong.enterprise_edition.cert_utils"

local mt_cache = { __mode = "k" }
local producers_cache = setmetatable({}, mt_cache)

local GENERIC_KAFKA_ERROR = "error sending message to Kafka topic."

local function is_auth_enabled(config)
  return config.strategy and config.mechanism
end

local function handle_error(error_object)
  local internal_message = error_object.internal_message or
      GENERIC_KAFKA_ERROR
  local external_message = error_object.external_message or
      GENERIC_KAFKA_ERROR
  local status_code = error_object.status_code or 500
  kong.log.err(internal_message)
  return kong.response.exit(status_code,
          { message = "Bad Gateway", error = external_message })
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

    client_id = conf.client_id
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
  kong.log.debug("creating a new Kafka Producer for configuration: ", tostring(conf))

  local err
  producer, err = create(conf)
  if not producer then
    return nil, err
  end

  producers_cache[conf] = producer

  return producer
end

---send message to kafka based on a given config
---@param conf table
---@param message string
---@return boolean or nil
---@return table or nil (error object)
local function send_message(conf, message)
  -- fetch certificate from the store
  if conf.security.certificate_id then
    local client_cert, client_priv_key, err = cert_utils.load_certificate(conf.security.certificate_id)
    if not client_cert or not client_priv_key or err ~= nil then
      local log_err = "failed to find or load certificate: " .. err
      return false, {
              status_code = 500,
              external_message = "could not load certificate",
              internal_message = log_err
          }
    end
    conf.security.client_cert = client_cert
    conf.security.client_priv_key = client_priv_key
  end

  local producer, err = get_or_create(conf)
  if not producer then
    return false, {
            status_code = 500,
            internal_message = "could not create a Kafka Producer from given configuration: " .. tostring(err),
            external_message = "could not create a Kafka Producer from given configuration: "
        }
  end

  local ok, p_err = producer:send(conf.topic, nil, message)
  if not ok then
    return false, {
            status_code = 500,
            external_message = "could not send message to topic",
            internal_message = "could not send message to topic " .. conf.topic .. ": " .. tostring(p_err)
        }
  end
  return true, {}
end

return {
    get_or_create = get_or_create,
    send_message = send_message,
    handle_error = handle_error,
}
