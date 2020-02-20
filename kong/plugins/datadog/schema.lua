local typedefs = require "kong.db.schema.typedefs"

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
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        default = { metrics = DEFAULT_METRICS },
        fields = {
          { host = typedefs.host({ required = true, default = "localhost" }), },
          { port = typedefs.port({ required = true, default = 8125 }), },
          { prefix = { type = "string", default = "kong" }, },
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
                  }, },
  }, }, }, }, }, }, }, },
}

