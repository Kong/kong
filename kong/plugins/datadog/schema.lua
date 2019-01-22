local typedefs = require "kong.db.schema.typedefs"

local STAT_NAMES = {
  "kong_latency",
  "latency",
  "request_count",
  "request_per_user",
  "request_size",
  "response_size",
  "status_count",
  "status_count_per_user",
  "unique_users",
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
    tags        = {"app:kong"}
  },
  {
    name      = "latency",
    stat_type = "timer",
    tags      = {"app:kong"}
  },
  {
    name      = "request_size",
    stat_type = "timer",
    tags      = {"app:kong"}
  },
  {
    name        = "status_count",
    stat_type   = "counter",
    sample_rate = 1,
    tags        = {"app:kong"}
  },
  {
    name      = "response_size",
    stat_type = "timer",
    tags      = {"app:kong"}
  },
  {
    name                = "unique_users",
    stat_type           = "set",
    consumer_identifier = "custom_id",
    tags                = {"app:kong"}
  },
  {
    name                = "request_per_user",
    stat_type           = "counter",
    sample_rate         = 1,
    consumer_identifier = "custom_id",
    tags                = {"app:kong"}
  },
  {
    name      = "upstream_latency",
    stat_type = "timer",
    tags      = {"app:kong"}
  },
  {
    name      = "kong_latency",
    stat_type = "timer",
    tags      = {"app:kong"}
  },
  {
    name                = "status_count_per_user",
    stat_type           = "counter",
    sample_rate         = 1,
    consumer_identifier = "custom_id",
    tags                = {"app:kong"}
  }
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
                    if_field = "name", if_match = { eq = "unique_users" },
                    then_field = "stat_type", then_match = { eq = "set" },
                  }, },

                  { conditional = {
                    if_field = "stat_type",
                    if_match = { one_of = { "counter", "gauge" }, },
                    then_field = "sample_rate",
                    then_match = { required = true },
                  }, },

                  { conditional = {
                    if_field = "name",
                    if_match = { one_of = { "status_count_per_user", "request_per_user", "unique_users" }, },
                    then_field = "consumer_identifier",
                    then_match = { required = true },
                  }, },

                  { conditional = {
                    if_field = "name",
                    if_match = { one_of = { "status_count", "status_count_per_user", "request_per_user" }, },
                    then_field = "stat_type",
                    then_match = { eq = "counter" },
                  }, },
  }, }, }, }, }, }, }, },
}

