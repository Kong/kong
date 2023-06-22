-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"
local constants = require "kong.plugins.statsd.constants"


local METRIC_NAMES = {
  "kong_latency", "latency", "request_count", "request_per_user",
  "request_size", "response_size", "status_count", "status_count_per_user",
  "unique_users", "upstream_latency",
  "status_count_per_workspace", "status_count_per_user_per_route",
  "shdict_usage",
  "cache_datastore_hits_total", "cache_datastore_misses_total",
}


local STAT_TYPES = {
  "counter", "gauge", "histogram", "meter", "set", "timer",
}


local CONSUMER_IDENTIFIERS = {
  "consumer_id", "custom_id", "username",
}

local SERVICE_IDENTIFIERS = {
  "service_id", "service_name", "service_host", "service_name_or_host",
}

local WORKSPACE_IDENTIFIERS = {
  "workspace_id", "workspace_name",
}


local DEFAULT_METRICS = {
  {
    name               = "request_count",
    stat_type          = "counter",
    sample_rate        = 1,
    service_identifier = nil,
  },
  {
    name               = "latency",
    stat_type          = "timer",
    service_identifier = nil,
  },
  {
    name               = "request_size",
    stat_type          = "timer",
    service_identifier = nil,
  },
  {
    name               = "status_count",
    stat_type          = "counter",
    sample_rate        = 1,
    service_identifier = nil,
  },
  {
    name               = "response_size",
    stat_type          = "timer",
    service_identifier = nil,
  },
  {
    name                = "unique_users",
    stat_type           = "set",
    consumer_identifier = nil,
    service_identifier  = nil,
  },
  {
    name                = "request_per_user",
    stat_type           = "counter",
    sample_rate         = 1,
    consumer_identifier = nil,
    service_identifier  = nil,
  },
  {
    name               = "upstream_latency",
    stat_type          = "timer",
    service_identifier = nil,
  },
  {
    name               = "kong_latency",
    stat_type          = "timer",
    service_identifier = nil,
  },
  {
    name                = "status_count_per_user",
    stat_type           = "counter",
    sample_rate         = 1,
    consumer_identifier = nil,
    service_identifier  = nil,
  },
  {
    name                 = "status_count_per_workspace",
    stat_type            = "counter",
    sample_rate          = 1,
    workspace_identifier = nil,
  },
  {
    name                = "status_count_per_user_per_route",
    stat_type           = "counter",
    sample_rate         = 1,
    consumer_identifier = nil,
    service_identifier  = nil,
  },
  {
    name               = "shdict_usage",
    stat_type          = "gauge",
    sample_rate        = 1,
    service_identifier = nil,
  },
  {
    name        = "cache_datastore_hits_total",
    stat_type   = "counter",
    sample_rate = 1,
  },
  {
    name        = "cache_datastore_misses_total",
    stat_type   = "counter",
    sample_rate = 1,
  },
}


local MUST_TYPE = {}

local MUST_IDENTIFIER = {}

for _, metric in ipairs(DEFAULT_METRICS) do
  local typ = metric.stat_type
  if typ == "counter" or typ == "set" or typ == "gauge" then
    if not MUST_TYPE[typ] then
      MUST_TYPE[typ] = { metric.name }
    else
      MUST_TYPE[typ][#MUST_TYPE[typ]+1] = metric.name
    end
  end

  for _, id in ipairs({ "service", "consumer", "workspace"}) do
    if metric[id .. "_identifier"] then
      if not MUST_IDENTIFIER[id] then
        MUST_IDENTIFIER[id] = { metric.name }
      else
        MUST_IDENTIFIER[id][#MUST_IDENTIFIER[id]+1] = metric.name
      end
    end
  end
end

return {
  name = "statsd-advanced",
  fields = {
    { protocols = typedefs.protocols },
    { consumer_group = typedefs.no_consumer_group },
    { config = {
        type = "record",
        fields = {
          { host = typedefs.host({ default = "localhost" }), },
          { port = typedefs.port({ default = 8125 }), },
          { prefix = { description = "String to prefix to each metric's name.", type = "string", default = "kong" }, },
          { metrics = { description = "List of Metrics to be logged.", type = "array",
              default = DEFAULT_METRICS,
              elements = {
                type = "record",
                fields = {
                  { name = { type = "string", required = true, one_of = METRIC_NAMES }, },
                  { stat_type = { type = "string", required = true, one_of = STAT_TYPES }, },
                  { sample_rate = { type = "number", gt = 0 }, },
                  { consumer_identifier = { type = "string", one_of = CONSUMER_IDENTIFIERS }, },
                  { service_identifier = { type = "string", one_of = SERVICE_IDENTIFIERS }, },
                  { workspace_identifier = { type = "string", one_of = WORKSPACE_IDENTIFIERS }, },
                },
                entity_checks = {
                  { conditional = {
                    if_field = "name",
                    if_match = { one_of = MUST_TYPE["set"] },
                    then_field = "stat_type",
                    then_match = { eq = "set" },
                  }, },
                  { conditional = {
                    if_field = "name",
                    if_match = { one_of = MUST_TYPE["counter"] },
                    then_field = "stat_type",
                    then_match = { eq = "counter" },
                  }, },
                  { conditional = {
                    if_field = "name",
                    if_match = { one_of = MUST_TYPE["gauge"] },
                    then_field = "stat_type",
                    then_match = { eq = "gauge" },
                  }, },
                  { conditional = {
                    if_field = "stat_type",
                    if_match = { one_of = { "counter", "gauge" }, },
                    then_field = "sample_rate",
                    then_match = { required = true },
                  }, },
                },
              },
          }, },
          { allow_status_codes = { description = "List of status code ranges that are allowed to be logged in metrics.", type = "array",
            elements = {
              type = "string",
              match = constants.REGEX_STATUS_CODE_RANGE,
            },
          }, },
          -- combine udp packet up to this value, don't combine if it's 0
          -- 65,507 bytes (65,535 − 8 byte UDP header − 20 byte IP header) -- Wikipedia
          { udp_packet_size = { description = "Combine UDP packet up to the size configured. If zero (0), don't combine the UDP packet. Must be a number between 0 and 65507 (inclusive).", type = "number", between = {0, 65507}, default = 0 }, },
          { use_tcp = { description = "Use TCP instead of UDP.", type = "boolean", default = false }, },
          { hostname_in_prefix = { description = "Include the `hostname` in the `prefix` for each metric name.", type = "boolean", default = false }, },
          { consumer_identifier_default = { description = "The default consumer identifier for metrics. This will take effect when a metric's consumer identifier is omitted. Allowed values are `custom_id`, `consumer_id`, `username`.", type = "string", required = true, default = "custom_id", one_of = CONSUMER_IDENTIFIERS }, },
          { service_identifier_default = { description = "The default service identifier for metrics. This will take effect when a metric's service identifier is omitted. Allowed values are `service_name_or_host`, `service_id`, `service_name`, `service_host`.", type = "string", required = true, default = "service_name_or_host", one_of = SERVICE_IDENTIFIERS }, },
          { workspace_identifier_default = { description = "The default workspace identifier for metrics. This will take effect when a metric's workspace identifier is omitted. Allowed values are `workspace_id`, `workspace_name`.   ", type = "string", required = true, default = "workspace_id", one_of = WORKSPACE_IDENTIFIERS }, },
          { queue = typedefs.queue },
        },
      },
    },
  },
}
