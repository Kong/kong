local typedefs = require "kong.db.schema.typedefs"


local ALGORITHMS = {
  "hmac-sha1",
  "hmac-sha256",
  "hmac-sha384",
  "hmac-sha512",
}


return {
  name = "hmac-auth",
  fields = {
    { consumer = typedefs.no_consumer },
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { hide_credentials = { description = "An optional boolean value telling the plugin to show or hide the credential from the upstream service. If `true`, the plugin strips the credential from the request (i.e. the `Authorization` header) before proxying it.", type = "boolean", required = true, default = false }, },
          { clock_skew = { description = "[Clock Skew](https://tools.ietf.org/html/draft-cavage-http-signatures-00#section-3.4) in seconds to prevent replay attacks.", type = "number", default = 300, gt = 0 }, },
          { anonymous = { description = "An optional string (Consumer UUID or username) value to use as an “anonymous” consumer if authentication fails. If empty (default null), the request will fail with an authentication failure `4xx`. Please note that this value must refer to the Consumer `id` or `username` attribute, and **not** its `custom_id`.", type = "string" }, },
          { validate_request_body = { description = "A boolean value telling the plugin to enable body validation.", type = "boolean", required = true, default = false }, },
          { enforce_headers = { description = "A list of headers that the client should at least use for HTTP signature creation.", type = "array",
              elements = { type = "string" },
              default = {},
          }, },
          { algorithms = { description = "A list of HMAC digest algorithms that the user wants to support. Allowed values are `hmac-sha1`, `hmac-sha256`, `hmac-sha384`, and `hmac-sha512`", type = "array",
              elements = { type = "string", one_of = ALGORITHMS },
              default = ALGORITHMS,
          }, },
        },
      },
    },
  },
}
