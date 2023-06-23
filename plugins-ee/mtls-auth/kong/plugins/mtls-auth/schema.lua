-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]
--- Copyright 2019 Kong Inc.
local typedefs = require("kong.db.schema.typedefs")

return {
  name = "mtls-auth",
  fields = {
    { consumer = typedefs.no_consumer },
    { protocols = typedefs.protocols_http },
    { consumer_group = typedefs.no_consumer_group },
    { config = {
        type = "record",
        fields = {
          { anonymous = { description = "An optional string (consumer UUID or username) value to use as an “anonymous” consumer if authentication fails. If empty (default null), the request fails with an authentication failure `4xx`. Note that this value must refer to the consumer `id` or `username` attribute, and **not** its `custom_id`.", type = "string" } },
          { consumer_by = { description = "Whether to match the subject name of the client-supplied certificate against consumer's `username` and/or `custom_id` attribute. If set to `[]` (the empty array), then auto-matching is disabled.", type = "array",
            elements = { type = "string", one_of = { "username", "custom_id" }},
            required = false,
            default = { "username", "custom_id" },
          }, },
          { ca_certificates = { description = "List of CA Certificates strings to use as Certificate Authorities (CA) when validating a client certificate. At least one is required but you can specify as many as needed. The value of this array is comprised of primary keys (`id`).", type = "array",
            required = true,
            elements = { type = "string", uuid = true, },
          }, },
          { cache_ttl = { description = "Cache expiry time in seconds.", type = "number",
            required = true,
            default = 60
          }, },
          { skip_consumer_lookup = { description = "Skip consumer lookup once certificate is trusted against the configured CA list.", type = "boolean",
            required = true,
            default = false
          }, },
          { allow_partial_chain = { description = "Allow certificate verification with only an intermediate certificate. When this is enabled, you don't need to upload the full chain to Kong Certificates.", type = "boolean",
            required = true,
            default = false
          }, },
          { authenticated_group_by = { description = "Certificate property to use as the authenticated group. Valid values are `CN` (Common Name) or `DN` (Distinguished Name). Once `skip_consumer_lookup` is applied, any client with a valid certificate can access the Service/API. To restrict usage to only some of the authenticated users, also add the ACL plugin (not covered here) and create allowed or denied groups of users.", required = false,
            type = "string",
            one_of = {"CN", "DN"},
            default = "CN"
          }, },
          { revocation_check_mode = { description = "Controls client certificate revocation check behavior. If set to `SKIP`, no revocation check is performed. If set to `IGNORE_CA_ERROR`, the plugin respects the revocation status when either OCSP or CRL URL is set, and doesn't fail on network issues. If set to `STRICT`, the plugin only treats the certificate as valid when it's able to verify the revocation status.", required = false,
            type = "string",
            one_of = {"SKIP", "IGNORE_CA_ERROR", "STRICT"},
            default = "IGNORE_CA_ERROR"
          }, },
          { http_timeout = { description = "HTTP timeout threshold in milliseconds when communicating with the OCSP server or downloading CRL.", type = "number",
            default = 30000,
          }, },
          { cert_cache_ttl = { description = "The length of time in milliseconds between refreshes of the revocation check status cache.", type = "number",
            default = 60000,
          }, },
          { send_ca_dn = { description = "Sends the distinguished names (DN) of the configured CA list in the TLS handshake message.", type = "boolean",
            default = false
          }, },
          { http_proxy_host = typedefs.host },
          { http_proxy_port = typedefs.port },
          { https_proxy_host = typedefs.host },
          { https_proxy_port = typedefs.port },
        },
        entity_checks = {
          { mutually_required = { "http_proxy_host", "http_proxy_port" } },
          { mutually_required = { "https_proxy_host", "https_proxy_port" } },
        }
    }, },
  },
}