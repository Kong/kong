-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local kong = kong
local cert_utils = require "kong.plugins.kafka-log.cert_utils"
local basic_serializer = require "kong.plugins.log-serializers.basic"
local producers = require "kong.plugins.kafka-log.producers"
local cjson_encode = require("cjson").encode

local KafkaLogHandler = {}

KafkaLogHandler.PRIORITY = 5
KafkaLogHandler.VERSION = "0.2.0"

--- Publishes a message to Kafka.
-- Must run in the context of `ngx.timer.at`.
local function timer_log(premature, conf, message)
  if premature then
    return
  end

  -- fetch certificate from the store
  if conf.security.certificate_id then
    local cert_obj, err = cert_utils.load_certificate(conf.security.certificate_id)
    if not cert_obj then
      kong.log.err("failed to find certificate: ", err)
      return kong.response.exit(500, { message = "Could not load certificate" })
    end

    conf.security.client_cert = cert_obj.cert
    conf.security.client_priv_key = cert_obj.priv_key
  end

  local producer, err = producers.get_or_create(conf)
  if not producer then
    kong.log.err("failed to create a Kafka Producer for a given configuration: ", err)
    return
  end

  local ok, err = producer:send(conf.topic, nil, cjson_encode(message))
  if not ok then
    kong.log.err("failed to send a message on topic ", conf.topic, ": ", err)
    return
  end
end


function KafkaLogHandler:log(conf, other)
  kong.log.notice("Creating timer")
  local message = basic_serializer.serialize(ngx)
  local ok, err = ngx.timer.at(0, timer_log, conf, message)
  if not ok then
    kong.log.err("failed to create timer: ", err)
  end
end

return KafkaLogHandler
