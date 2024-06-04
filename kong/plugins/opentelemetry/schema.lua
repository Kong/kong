-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"
local Schema = require "kong.db.schema"

local function custom_validator(attributes)
  for _, v in pairs(attributes) do
    local vtype = type(v)
    if vtype ~= "string" and
       vtype ~= "number" and
       vtype ~= "boolean"
    then
      return nil, "invalid type of value: " .. vtype
    end

    if vtype == "string" and #v == 0 then
      return nil, "required field missing"
    end
  end

  return true
end

local resource_attributes = Schema.define {
  type = "map",
  keys = { type = "string", required = true },
  -- TODO: support [string, number, boolean]
  values = { type = "string", required = true },
  custom_validator = custom_validator,
}

return {
  name = "opentelemetry",
  fields = {
    { protocols = typedefs.protocols_http }, -- TODO: support stream mode
    { consumer_group = typedefs.no_consumer_group },
    { config = {
      type = "record",
      fields = {
        { traces_endpoint = typedefs.url { referenceable = true } }, -- OTLP/HTTP
        { logs_endpoint = typedefs.url { referenceable = true } },
        { headers = { description = "The custom headers to be added in the HTTP request sent to the OTLP server. This setting is useful for adding the authentication headers (token) for the APM backend.", type = "map",
          keys = typedefs.header_name,
          values = {
            type = "string",
            referenceable = true,
          },
        } },
        { resource_attributes = resource_attributes },
        { queue = typedefs.queue {
          default = {
            max_batch_size = 200,
          },
        } },
        { batch_span_count = {
            description = "The number of spans to be sent in a single batch.",
            type = "integer",
            deprecation = {
              message = "opentelemetry: config.batch_span_count is deprecated, please use config.queue.max_batch_size instead",
              removal_in_version = "4.0",
              old_default = 200 }, }, },
        { batch_flush_delay = {
            description = "The delay, in seconds, between two consecutive batches.",
            type = "integer",
            deprecation = {
              message = "opentelemetry: config.batch_flush_delay is deprecated, please use config.queue.max_coalescing_delay instead",
              removal_in_version = "4.0",
              old_default = 3, }, }, },
        { connect_timeout = typedefs.timeout { default = 1000 } },
        { send_timeout = typedefs.timeout { default = 5000 } },
        { read_timeout = typedefs.timeout { default = 5000 } },
        { http_response_header_for_traceid = { type = "string", default = nil }},
        { header_type = {
              type = "string",
              deprecation = {
                message = "opentelemetry: config.header_type is deprecated, please use config.propagation options instead",
                removal_in_version = "4.0",
                old_default = "preserve" },
              required = false,
              default = "preserve",
              one_of = { "preserve", "ignore", "b3", "b3-single", "w3c", "jaeger", "ot", "aws", "gcp", "datadog" } } },
        { sampling_rate = {
          description = "Tracing sampling rate for configuring the probability-based sampler. When set, this value supersedes the global `tracing_sampling_rate` setting from kong.conf.",
          type = "number",
          between = {0, 1},
          required = false,
          default = nil,
        } },
        { propagation = typedefs.propagation {
          default = {
            default_format = "w3c",
          },
        } },
      },
      entity_checks = {
        { at_least_one_of = {
          "traces_endpoint",
          "logs_endpoint",
        } },
      },
      shorthand_fields = {
        -- TODO: deprecated fields, to be removed in Kong 4.0
        {
          endpoint = typedefs.url {
            referenceable = true,
            deprecation = {
              message = "OpenTelemetry: config.endpoint is deprecated, please use config.traces_endpoint instead",
              removal_in_version = "4.0", },
            func = function(value)
              return { traces_endpoint = value }
            end,
          },
        },
      }
    }, },
  },
}
