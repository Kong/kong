local typedefs = require "kong.db.schema.typedefs"

return {
  name = "kafka-upstream",
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
                  { host = typedefs.host({ required = true }), },
                  { port = typedefs.port({ required = true }), },
                },
              },
            },
          },
          { topic = { type = "string", required = true }, },
          { timeout = { type = "integer", default = 10000 }, },
          { keepalive = { type = "integer", default = 60000 }, },

          { forward_method = { type = "boolean", default = false } },
          { forward_uri = { type = "boolean", default = false } },
          { forward_headers = { type = "boolean",default = false } },
          { forward_body = { type = "boolean", default = true } },

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

        entity_checks = {
          { custom_entity_check = {
              field_sources = { "forward_method", "forward_uri", "forward_headers", "forward_body" },
              fn = function(entity)
                if entity.forward_method or entity.forward_uri
                or entity.forward_headers or entity.forward_body then
                  return true
                end
                return nil, "at least one of these attributes must be true: forward_method, forward_uri, forward_headers, forward_body"
              end
            },
          },
        },
      },
    },
  },
}
