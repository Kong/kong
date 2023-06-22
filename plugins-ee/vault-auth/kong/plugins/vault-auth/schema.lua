-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"


return {
  name = "vault-auth",
  fields = {
    { protocols = typedefs.protocols_http },
    { consumer_group = typedefs.no_consumer_group },
    { consumer = typedefs.no_consumer },
    { config = {
        type = "record",
        fields = {
          { access_token_name = { description = "Describes an array of comma-separated parameter names where the plugin looks for an access token. The client must send the access token in one of those key names, and the plugin will try to read the credential from a header or the querystring parameter with the same name. The key names can only contain [a-z], [A-Z], [0-9], [_], and [-].", type = "string",
              required = true,
              elements = typedefs.header_name,
              default = "access_token",
          }, },
          { secret_token_name = { description = "Describes an array of comma-separated parameter names where the plugin looks for a secret token. The client must send the secret in one of those key names, and the plugin will try to read the credential from a header or the querystring parameter with the same name. The key names can only contain [a-z], [A-Z], [0-9], [_], and [-].", type = "string",
              required = true,
              elements = typedefs.header_name,
              default = "secret_token",
          }, },
          { vault = { description = "A reference to an existing `vault` object within the database. `vault` entities define the connection and authentication parameters used to connect to a Vault HTTP(S) API.", type = "foreign", reference = "vault_auth_vaults", required = true } },
          { hide_credentials = { description = "An optional boolean value telling the plugin to show or hide the credential from the upstream service. If `true`, the plugin will strip the credential from the request (i.e. the header or querystring containing the key) before proxying it.", type = "boolean", default = false }, },
          { anonymous = { description = "An optional string (consumer UUID or username) value to use as an “anonymous” consumer if authentication fails. If empty (default null), the request fails with an authentication failure `4xx`. Note that this value must refer to the consumer `id` or `username` attribute, and **not** its `custom_id`.", type = "string" }, },
          { tokens_in_body = { description = "If enabled, the plugin will read the request body (if said request has one and its MIME type is supported) and try to find the key in it. Supported MIME types are `application/www-form-urlencoded`, `application/json`, and `multipart/form-data`.", type = "boolean", default = false }, },
          { run_on_preflight = { description = "A boolean value that indicates whether the plugin should run (and try to authenticate) on `OPTIONS` preflight requests. If set to `false`, then `OPTIONS` requests will always be allowed.", type = "boolean", default = true }, },
        },
    }, },
  },
}