local typedefs = require "kong.db.schema.typedefs"


return {
  name = "brain",
  fields = {
    { consumer = typedefs.no_consumer },
    { run_on = typedefs.run_on_first },
    { protocols = typedefs.protocols_http },
    {
      config = {
        type = "record",
        fields = {
          { environment = { type = "string" } },
          { retry_count = { type = "number", default = 10 } },
          { queue_size = { type = "number", default = 1000 } },
          { flush_timeout = { type = "number", default = 2 } },
          { log_bodies = { type = "boolean", default = false } },
          { service_token = { type = "string", required = true } },
          { connection_timeout = { type = "number", default = 30 } },
          { host = { type = "string", required = true, default = "collector.brain.kong.com" } },
          { port = { type = "number", required = true, default = 443 } },
          { https = { type = "boolean", default = true } },
          { https_verify = { type = "boolean", default = false } },
        },
      },
    },
  },
}
