local typedefs = require "kong.db.schema.typedefs"


return {
  name = "invalidations",
  fields = {
    {
      protocols = typedefs.protocols {
        default = {
          "http",
          "https",
          "tcp",
          "tls",
          "grpc",
          "grpcs"
        },
      },
    },
    {
      config = {
        type = "record",
        fields = {
        },
      },
    },
  },
}
