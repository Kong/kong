local typedefs = require "kong.db.schema.typedefs"

local PLUGIN_NAME = "standard-webhooks"

local schema = {
  name = PLUGIN_NAME,
  fields = {
    { consumer = typedefs.no_consumer },
    { protocols = typedefs.protocols_http },
    {
      config = {
        type = "record",
        fields = {
          {
            secret_v1 = {
              type = "string",
              required = true,
              description = "Webhook secret",
              referenceable = true,
              encrypted = true,
            },
          },
          {
            tolerance_second = {
              description = "Tolerance of the webhook timestamp in seconds. If the webhook timestamp is older than this number of seconds, it will be rejected with a '400' response.",
              type = "integer",
              required = true,
              gt = -1,
              default = 5 * 60
            }
          }
        }
      }
    }
  }
}

return schema
