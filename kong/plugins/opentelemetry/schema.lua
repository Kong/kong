local typedefs = require "kong.db.schema.typedefs"
local Schema = require "kong.db.schema"
local deprecation = require("kong.deprecation")

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
    { config = {
      type = "record",
      fields = {
        { endpoint = typedefs.url { required = true, referenceable = true } }, -- OTLP/HTTP
        { headers = { description = "The custom headers to be added in the HTTP request sent to the OTLP server. This setting is useful for adding the authentication headers (token) for the APM backend.", type = "map",
          keys = typedefs.header_name,
          values = {
            type = "string",
            referenceable = true,
          },
        } },
        { resource_attributes = resource_attributes },
        { queue = typedefs.queue },
        { batch_span_count = { description = "The number of spans to be sent in a single batch.", type = "integer" } },
        { batch_flush_delay = { description = "The delay, in seconds, between two consecutive batches.", type = "integer" } },
        { connect_timeout = typedefs.timeout { default = 1000 } },
        { send_timeout = typedefs.timeout { default = 5000 } },
        { read_timeout = typedefs.timeout { default = 5000 } },
        { http_response_header_for_traceid = { type = "string", default = nil }},
        { header_type = { type = "string", required = false, default = "preserve",
                          one_of = { "preserve", "ignore", "b3", "b3-single", "w3c", "jaeger", "ot", "aws" } } },
      },
      entity_checks = {
        { custom_entity_check = {
          field_sources = { "batch_span_count", "batch_flush_delay" },
          fn = function(entity)
            if (entity.batch_span_count or ngx.null) ~= ngx.null and entity.batch_span_count ~= 200 then
              deprecation("opentelemetry: config.batch_span_count is deprecated, please use config.queue.max_batch_size instead",
                          { after = "4.0", })
            end
            if (entity.batch_flush_delay or ngx.null) ~= ngx.null and entity.batch_flush_delay ~= 3 then
              deprecation("opentelemetry: config.batch_flush_delay is deprecated, please use config.queue.max_coalescing_delay instead",
                          { after = "4.0", })
            end
            return true
          end
        } },
      },
    }, },
  },
}
