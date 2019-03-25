local typedefs        = require "kong.db.schema.typedefs"


return {
  name = "forward-proxy",
  fields = {
    { config = {
        type = "record",
        fields = {
          { proxy_host = typedefs.host {required = true} },
          { proxy_port = typedefs.port {required = true} },
          { proxy_scheme = {
            type = "string",
            one_of = { "http" },
            required = true,
            default = "http",
          }},
          { https_verify = {
            type = "boolean",
            required = true,
            default = false,
          }},
        }
      }
    }
  }
}
