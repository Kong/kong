local typedefs = require "kong.db.schema.typedefs"

return {
  name = "kafka-log",
  fields = {
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { bootstrap_servers = {
              type = "set",
              elements = {
                type = "record",
                fields = {
                  { host = typedefs.ip({ required = true }), },
                  { port = typedefs.port({ required = true }), },
                },
              },
            },
          },
          { topic = { type = "string", required = true }, },
          { timeout = { type = "integer", default = 10000 }, },
          { keepalive = { type = "integer", default = 60000 }, },
          { producer_request_acks = { type = "integer", default = 1, one_of = { -1, 0, 1 }, }, },
          { producer_request_timeout = { type = "integer", default = 2000 }, },
          { producer_request_limits_messages_per_request = { type = "integer", default = 200 }, },
          { producer_request_limits_bytes_per_request = { type = "integer", default = 1048576 }, },
          { producer_request_retries_max_attempts = { type = "integer", default = 10 }, },
          { producer_request_retries_backoff_timeout = { type = "integer", default = 100 }, },
          { producer_async = { type = "boolean", default = true }, },
          { producer_async_flush_timeout = { type = "integer", default = 1000 }, },
          { producer_async_buffering_limits_messages_in_memory = { type = "integer", default = 50000 }, },
        },
      },
    },
  },
}
