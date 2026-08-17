local typedefs = require "kong.db.schema.typedefs"


return {
  name = "correlation-id",
  fields = {
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { header_name = { description = "The HTTP header name to use for the correlation ID.", type = "string", default = "Kong-Request-ID" }, },
          { generator = { description = "The generator to use for the correlation ID. Accepted values are `uuid`, `uuid#counter`, and `tracker`. See [Generators](#generators).",
                          type = "string", default = "uuid#counter", required = true, one_of = { "uuid", "uuid#counter", "tracker" }, }, },
          { echo_downstream = { description = "Whether to echo the header back to downstream (the client).", type = "boolean", required = true, default = false, }, },
        },
      },
    },
  },
}
