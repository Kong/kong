local typedefs = require "kong.db.schema.typedefs"


return {
  name = "basic-auth",
  fields = {
    { consumer = typedefs.no_consumer },
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { anonymous = { description = "An optional string (Consumer UUID or username) value to use as an “anonymous” consumer if authentication fails. If empty (default null), the request will fail with an authentication failure `4xx`. Please note that this value must refer to the Consumer `id` or `username` attribute, and **not** its `custom_id`.", type = "string" }, },
          { hide_credentials = { description = "An optional boolean value telling the plugin to show or hide the credential from the upstream service. If `true`, the plugin will strip the credential from the request (i.e. the `Authorization` header) before proxying it.", type = "boolean", required = true, default = false }, },
          { realm = { description = "When authentication or authorization fails, or there is an unexpected error, the plugin sends an `WWW-Authenticate` header with the `realm` attribute value.", type = "string", required = true, default = "service" }, },
    }, }, },
  },
}
