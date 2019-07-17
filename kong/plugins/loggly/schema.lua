local typedefs = require "kong.db.schema.typedefs"

local severity = {
  type = "string",
  default = "info",
  one_of = { "debug", "info", "notice", "warning", "err", "crit", "alert", "emerg" },
}

return {
  name = "loggly",
  fields = {
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { host = typedefs.host({ default = "logs-01.loggly.com" }), },
          { port = typedefs.port({ default = 514 }), },
          { key = { type = "string", required = true }, },
          { tags = {
              type = "set",
              default = { "kong" },
              elements = { type = "string" },
          }, },
          { log_level = severity },
          { successful_severity = severity },
          { client_errors_severity = severity },
          { server_errors_severity = severity },
          { timeout = { type = "number", default = 10000 }, },
        },
      },
    },
  },
}
