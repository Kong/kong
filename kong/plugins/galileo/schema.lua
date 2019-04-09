local typedefs = require "kong.db.schema.typedefs"

return {
  name = "galileo",
  fields = {
    { config = {
        type = "record",
        fields = {
          { environment = { type = "string" }, },
          { retry_count = { type = "integer", default = 10 }, },
          { queue_size = { type = "integer", default = 1000 }, },
          { flush_timeout = { type = "number", default = 2 }, },
          { log_bodies = { type = "boolean", default = false }, },
          { service_token = { type = "string", required = true }, },
          { connection_timeout = { type = "number", default = 30 }, },
          { host = typedefs.host({ required = true, default = "collector.galileo.mashape.com" }) },
          { port = typedefs.port({ required = true, default = 443 }) },
          { https = { type = "boolean", default = true }, },
          { https_verify = { type = "boolean", default = false }, }
        },
      }
    }
  }
}
