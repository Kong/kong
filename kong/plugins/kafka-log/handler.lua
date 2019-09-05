local basic_serializer = require "kong.plugins.log-serializers.basic"
local producers = require "kong.plugins.kafka-log.producers"
local cjson_encode = require("cjson").encode

local KafkaLogHandler = {}

KafkaLogHandler.PRIORITY = 5
KafkaLogHandler.VERSION = "0.0.1"

--- Publishes a message to Kafka.
-- Must run in the context of `ngx.timer.at`.
local function timer_log(premature, conf, message)
  if premature then
    return
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
  local message = basic_serializer.serialize(ngx)
  local ok, err = ngx.timer.at(0, timer_log, conf, message)
  if not ok then
    kong.log.err("failed to create timer: ", err)
  end
end

return KafkaLogHandler
