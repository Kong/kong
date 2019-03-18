-- add vitals metrics
local vitals = require "kong.vitals"
local constants = require "kong.plugins.statsd-advanced.constants"
local typedefs = require "kong.db.schema.typedefs"


local ee_metrics = vitals.logging_metrics or {}


local METRIC_NAMES = {
  "kong_latency", "latency", "request_count", "request_per_user",
  "request_size", "response_size", "status_count", "status_count_per_user",
  "unique_users", "upstream_latency",
  -- EE only
  "status_count_per_workspace", "status_count_per_user_per_route",
  "shdict_usage",
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
  "workspace_id", "workspace_name"
}

local DEFAULT_METRICS = {
  {
    name               = "request_count",
    stat_type          = "counter",
    sample_rate        = 1,
    service_identifier = "service_name_or_host"
  },
  {
    name               = "latency",
    stat_type          = "timer",
    service_identifier = "service_name_or_host",
  },
  {
    name               = "request_size",
    stat_type          = "timer",
    service_identifier = "service_name_or_host",
  },
  {
    name               = "status_count",
    stat_type          = "counter",
    sample_rate        = 1,
    service_identifier = "service_name_or_host",
  },
  {
    name               = "response_size",
    stat_type          = "timer",
    service_identifier = "service_name_or_host",
  },
  {
    name                = "unique_users",
    stat_type           = "set",
    consumer_identifier = "custom_id",
    service_identifier  = "service_name_or_host",
  },
  {
    name                = "request_per_user",
    stat_type           = "counter",
    sample_rate         = 1,
    consumer_identifier = "custom_id",
    service_identifier  = "service_name_or_host",
  },
  {
    name               = "upstream_latency",
    stat_type          = "timer",
    service_identifier = "service_name_or_host",
  },
  {
    name               = "kong_latency",
    stat_type          = "timer",
    service_identifier = "service_name_or_host",
  },
  {
    name                = "status_count_per_user",
    stat_type           = "counter",
    sample_rate         = 1,
    consumer_identifier = "custom_id",
    service_identifier  = "service_name_or_host",
  },
  -- EE only
  {
    name                 = "status_count_per_workspace",
    stat_type            = "counter",
    sample_rate          = 1,
    workspace_identifier = "workspace_id",
  },
  {
    name                = "status_count_per_user_per_route",
    stat_type           = "counter",
    sample_rate         = 1,
    consumer_identifier = "custom_id",
    service_identifier  = "service_name_or_host",
  },
  {
    name               = "shdict_usage",
    stat_type          = "gauge",
    sample_rate        = 1,
    service_identifier = "service_name_or_host",
  },
}

local MUST_TYPE = {}

local MUST_IDENTIFIER = {}

for _, group in pairs(ee_metrics) do
  for metric, metric_type in pairs(group) do
    METRIC_NAMES[#METRIC_NAMES+1] = metric
    DEFAULT_METRICS[#DEFAULT_METRICS + 1] = {
      name        = metric,
      stat_type   = metric_type,
      sample_rate = 1
    }
  end
end

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
    { config = {
      type = "record",
      fields = {
        { host = typedefs.host({ default = "localhost" }), },
        { port = typedefs.port({ default = 8125 }), },
        { prefix = { type = "string", default = "kong" }, },
        { metrics = {
          type = "array",
          default = DEFAULT_METRICS,
          elements = {
            type = "record",
            fields = {
              { name = { type = "string", required = true, one_of = METRIC_NAMES }, },
              { stat_type = { type = "string", required = true, one_of = STAT_TYPES }, },
              { sample_rate = { type = "number", gt = 0 }, },
              { consumer_identifier = { type = "string", one_of = CONSUMER_IDENTIFIERS }, },
              -- allow nil service_identifier for ce schema service_identifier is not defined
              -- allow nil workspace_identifier for ce schema workspace_identifier is not defined
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

              { conditional = {
                  if_field = "name",
                  if_match = { one_of = MUST_IDENTIFIER["consumer"], },
                  then_field = "consumer_identifier",
                  then_match = { required = true },
              }, },

              { conditional = {
                if_field = "name",
                if_match = { one_of = MUST_IDENTIFIER["workspace"], },
                then_field = "workspace_identifier",
                then_match = { required = true },
              }, },

              -- allow nil service_identifier for ce schema service_identifier is not defined
            },
          },
        }, },
        -- EE only
        { allow_status_codes = {
          type = "array",
          elements = {
            type = "string",
            match = constants.REGEX_STATUS_CODE_RANGE,
          },
        }, },
        -- combine udp packet up to this value, don't combine if it's 0
        -- 65,507 bytes (65,535 − 8 byte UDP header − 20 byte IP header) -- Wikipedia
        { udp_packet_size = { type = "number", between = {0, 65507}, default = 0 }, },
        { use_tcp = { type = "boolean", default = false }, },
        { hostname_in_prefix = { type = "boolean", default = false }, },
      }
    }, },
  }
}
