local typedefs = require "kong.db.schema.typedefs"
local deprecation = require("kong.deprecation")

local STAT_NAMES = {
  "kong_latency",
  "latency",
  "request_count",
  "request_size",
  "response_size",
  "upstream_latency",
}

local STAT_TYPES = {
  "counter",
  "gauge",
  "histogram",
  "meter",
  "set",
  "timer",
  "distribution",
}

local CONSUMER_IDENTIFIERS = {
  "consumer_id",
  "custom_id",
  "username",
}

local DEFAULT_METRICS = {
  {
    name        = "request_count",
    stat_type   = "counter",
    sample_rate = 1,
    tags        = {"app:kong" },
    consumer_identifier = "custom_id"
  },
  {
    name      = "latency",
    stat_type = "timer",
    tags      = {"app:kong"},
    consumer_identifier = "custom_id"
  },
  {
    name      = "request_size",
    stat_type = "timer",
    tags      = {"app:kong"},
    consumer_identifier = "custom_id"
  },
  {
    name      = "response_size",
    stat_type = "timer",
    tags      = {"app:kong"},
    consumer_identifier = "custom_id"
  },
  {
    name      = "upstream_latency",
    stat_type = "timer",
    tags      = {"app:kong"},
    consumer_identifier = "custom_id"
  },
  {
    name      = "kong_latency",
    stat_type = "timer",
    tags      = {"app:kong"},
    consumer_identifier = "custom_id"
  },
}


return {
  name = "datadog",
  fields = {
    { protocols = typedefs.protocols },
    { config = {
        type = "record",
        fields = {
          { host = typedefs.host({ referenceable = true, default = "localhost" }), },
          { port = typedefs.port({ default = 8125 }), },
          { prefix = { type = "string", default = "kong" }, },
          { service_name_tag = { type = "string", default = "name" }, },
          { status_tag = { type = "string", default = "status" }, },
          { consumer_tag = { type = "string", default = "consumer" }, },
          { retry_count = { type = "integer" }, },
          { queue_size = { type = "integer" }, },
          { flush_timeout = { type = "number" }, },
          { queue = typedefs.queue },
          { metrics = {
              type     = "array",
              required = true,
              default  = DEFAULT_METRICS,
              elements = {
                type = "record",
                fields = {
                  { name = { type = "string", required = true, one_of = STAT_NAMES }, },
                  { stat_type = { type = "string", required = true, one_of = STAT_TYPES }, },
                  { tags = { type = "array", elements = { type = "string", match = "^.*[^:]$" }, }, },
                  { sample_rate = { type = "number", between = { 0, 1 }, }, },
                  { consumer_identifier = { type = "string", one_of = CONSUMER_IDENTIFIERS }, },
                },
                entity_checks = {
                  { conditional = {
                    if_field = "stat_type",
                    if_match = { one_of = { "counter", "gauge" }, },
                    then_field = "sample_rate",
                    then_match = { required = true },
                  }, }, }, }, },
          },
        },

        entity_checks = {
          { custom_entity_check = {
              field_sources = { "retry_count", "queue_size", "flush_timeout" },
              fn = function(entity)
                if entity.retry_count and entity.retry_count ~= 10 then
                  deprecation("datadog: config.retry_count no longer works, please use config.queue.max_retry_time instead",
                    { after = "4.0", })
                end
                if entity.queue_size and entity.queue_size ~= 1 then
                  deprecation("datadog: config.queue_size no longer works, please use config.queue.max_batch_size instead",
                    { after = "4.0", })
                end
                if entity.flush_timeout and entity.flush_timeout ~= 2 then
                  deprecation("datadog: config.flush_timeout no longer works, please use config.queue.max_coalescing_delay instead",
                    { after = "4.0", })
                end
                return true
              end
          } },
        },
      },
    },
  },
}
