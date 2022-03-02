local typedefs = require "kong.db.schema.typedefs"

return {
  name = "opentelemetry",
  fields = {
    { config = {
        type = "record",
        fields = {
          { http_endpoint = typedefs.url }, -- OTLP/HTTP /v1/traces
          { sample_ratio = 
            { type = "number",
              default = 0.001,
              between = { 0, 1 } 
            }
          },
        },
    }, },
  },
}
