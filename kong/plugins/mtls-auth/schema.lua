--- Copyright 2019 Kong Inc.


local typedefs = require("kong.db.schema.typedefs")


return {
  name = "mtls-auth",
  fields = {
    { consumer = typedefs.no_consumer },
    { run_on = typedefs.run_on_first },
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { anonymous = { type = "string", uuid = true, legacy = true }, },
          { consumer_by = {
            type = "array",
            elements = { type = "string", one_of = { "username", "custom_id" }},
            required = false,
            default = { "username", "custom_id" },
          }, },
          { ca_certificates = {
            type = "array",
            required = true,
            elements = { type = "string", uuid = true, },
          }, },
          { cache_ttl = {
            type = "number",
            required = true,
            default = 60
          }, },
        },
    }, },
  },
}
