local typedefs = require "kong.db.schema.typedefs"


return {
  name = "key-auth",
  fields = {
    { consumer = typedefs.no_consumer },
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { key_names = { description = "Describes an array of parameter names where the plugin will look for a key. The key names may only contain [a-z], [A-Z], [0-9], [_] underscore, and [-] hyphen.", type = "array",
              required = true,
              elements = typedefs.header_name,
              default = { "apikey" },
          }, },
          { hide_credentials = { description = "An optional boolean value telling the plugin to show or hide the credential from the upstream service. If `true`, the plugin strips the credential from the request.", type = "boolean", required = true, default = false }, },
          { anonymous = { description = "An optional string (consumer UUID or username) value to use as an “anonymous” consumer if authentication fails. If empty (default null), the request will fail with an authentication failure `4xx`.", type = "string" }, },
          { key_in_header = { description = "If enabled (default), the plugin reads the request header and tries to find the key in it.", type = "boolean", required = true, default = true }, },
          { key_in_query = { description = "If enabled (default), the plugin reads the query parameter in the request and tries to find the key in it.", type = "boolean", required = true, default = true }, },
          { key_in_body = { description = "If enabled, the plugin reads the request body. Supported MIME types: `application/www-form-urlencoded`, `application/json`, and `multipart/form-data`.", type = "boolean", required = true, default = false }, },
          { run_on_preflight = { description = "A boolean value that indicates whether the plugin should run (and try to authenticate) on `OPTIONS` preflight requests. If set to `false`, then `OPTIONS` requests are always allowed.", type = "boolean", required = true, default = true }, },
          { realm = { description = "When authentication fails the plugin sends `WWW-Authenticate` header with `realm` attribute value.", type = "string", required = false }, },
        },
    }, },
  },
}
