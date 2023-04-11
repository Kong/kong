local typedefs = require "kong.db.schema.typedefs"


return {
  name = "key-auth",
  fields = {
    { consumer = typedefs.no_consumer },
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { key_names = { description = "Describes an array of parameter names where the plugin will look for a key. The client must send the\nauthentication key in one of those key names, and the plugin will try to read the credential from a\nheader, request body, or query string parameter with the same name.\n<br>**Note**: The key names may only contain [a-z], [A-Z], [0-9], [_] underscore, and [-] hyphen.", type = "array",
              required = true,
              elements = typedefs.header_name,
              default = { "apikey" },
          }, },
          { hide_credentials = { description = "An optional boolean value telling the plugin to show or hide the credential from the upstream service. If `true`,\nthe plugin strips the credential from the request (i.e., the header, query string, or request body containing the key) before proxying it.", type = "boolean", required = true, default = false }, },
          { anonymous = { description = "An optional string (consumer UUID or username) value to use as an “anonymous” consumer if authentication fails. If empty (default null), the request will fail with an authentication failure `4xx`. Note that this value must refer to the consumer `id` or `username` attribute, and **not** its `custom_id`.", type = "string" }, },
          { key_in_header = { description = "If enabled (default), the plugin reads the request header and tries to find the key in it.", type = "boolean", required = true, default = true }, },
          { key_in_query = { description = "If enabled (default), the plugin reads the query parameter in the request and tries to find the key in it.", type = "boolean", required = true, default = true }, },
          { key_in_body = { description = "If enabled, the plugin reads the request body (if said request has one and its MIME type is supported) and tries to find the key in it. Supported MIME types: `application/www-form-urlencoded`, `application/json`, and `multipart/form-data`.", type = "boolean", required = true, default = false }, },
          { run_on_preflight = { description = "A boolean value that indicates whether the plugin should run (and try to authenticate) on `OPTIONS` preflight requests.\nIf set to `false`, then `OPTIONS` requests are always allowed.", type = "boolean", required = true, default = true }, },
        },
    }, },
  },
}
