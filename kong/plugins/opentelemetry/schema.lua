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
    { config = {
      type = "record",
      fields = {
        { endpoint = typedefs.url { required = true } }, -- OTLP/HTTP
        { headers = { description = "The custom headers to be added in the HTTP request sent to the OTLP server.\nThis setting is useful for adding the authentication headers (token)\nfor the APM backend.", type = "map",
          keys = typedefs.header_name,
          values = {
            type = "string",
            referenceable = true,
          },
        } },
        { resource_attributes = resource_attributes },
        { batch_span_count = { description = "The number of spans to be sent in a single batch.", type = "integer", required = true, default = 200 } },
        { batch_flush_delay = { description = "The delay, in seconds, between two consecutive batches.", type = "integer", required = true, default = 3 } },
        { connect_timeout = typedefs.timeout { default = 1000 } },
        { send_timeout = typedefs.timeout { default = 5000 } },
        { read_timeout = typedefs.timeout { default = 5000 } },
        { http_response_header_for_traceid = { type = "string", default = nil }},
      },
    }, },
  },
}
