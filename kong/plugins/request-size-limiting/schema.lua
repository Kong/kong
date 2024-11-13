local typedefs = require "kong.db.schema.typedefs"
local handler = require "kong.plugins.request-size-limiting.handler"


local size_units = handler.size_units


return {
  name = "request-size-limiting",
  fields = {
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { allowed_payload_size = { description = "Allowed request payload size in megabytes. Default is `128` megabytes (128000000 bytes).", type = "integer", default = 128 }, },
          { size_unit = { description = "Size unit can be set either in `bytes`, `kilobytes`, or `megabytes` (default). This configuration is not available in versions prior to Kong Gateway 1.3 and Kong Gateway (OSS) 2.0.", type = "string", required = true, default = size_units[1], one_of = size_units }, },
          { require_content_length = { description = "Set to `true` to ensure a valid `Content-Length` header exists before reading the request body.", type = "boolean", required = true, default = false }, },
        },
      },
    },
  },
}
