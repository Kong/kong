local typedefs = require "kong.db.schema.typedefs"

return {
  name = "zipkin",
  fields = {
    { config = {
        type = "record",
        fields = {
          { http_endpoint = typedefs.url{ required = true } },
          { sample_ratio = { type = "number",
                             default = 0.001,
                             between = { 0, 1 } } },
                                        { default_service_name = { type = "string", default = nil } },
          { include_credential = { type = "boolean", required = true, default = true } },
          { traceid_byte_count = { type = "integer", required = true, default = 16, one_of = { 8, 16 } } },
          { header_type = { type = "string", required = true, default = "preserve",
                            one_of = { "preserve", "b3", "b3-single", "w3c" } } },
        },
    }, },
  },
}
