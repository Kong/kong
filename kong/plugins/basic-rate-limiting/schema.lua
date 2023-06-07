local typedefs = require "kong.db.schema.typedefs"

return {
  name = "basic-rate-limiting",
  fields = {
    { consumer = typedefs.no_consumer },
    { service = typedefs.no_service },
    { route = typedefs.no_route },
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { minute = { description = "The number of HTTP requests that can be made per minute.", type = "number", gt = 0 }, },
          { error_code = { description = "Set a custom error code to return when the rate limit is exceeded.", type = "number", default = 429, gt = 0 }, },
          { error_message = { description = "Set a custom error message to return when the rate limit is exceeded.", type = "string", default = "API rate limit exceeded" }, },
        },
      },
    },
  },
}