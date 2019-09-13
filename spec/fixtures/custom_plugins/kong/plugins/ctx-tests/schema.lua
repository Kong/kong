local typedefs = require "kong.db.schema.typedefs"

-- TODO: At the moment this tests the happy case. Perhaps it could be extended to work
--      even with unhappy cases, e.g. together with error-generator plugin. Or the plugin
--      could be made to error by itself.
return {
  name = "ctx-tests",
  fields = {
    {
      protocols = typedefs.protocols { default = { "http", "https", "tcp", "tls", "grpc", "grpcs" } },
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
