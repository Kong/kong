local typedefs = require "kong.db.schema.typedefs"


return {
  name = "correlation-id",
  fields = {
    { run_on = typedefs.run_on_first },
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { header_name = { type = "string", default = "Kong-Request-ID" }, },
          { generator = { type = "string", default = "uuid#counter",
                          one_of = { "uuid", "uuid#counter", "tracker" }, }, },
          { echo_downstream = { type = "boolean", default = false, }, },
        },
      },
    },
  },
}
