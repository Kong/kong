-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"
local handler = require "kong.plugins.oauth2-introspection.handler"


local consumer_by_fields = handler.consumer_by_fields
local CONSUMER_BY_DEFAULT = handler.CONSUMER_BY_DEFAULT


return {
  name = "oauth2-introspection",
  fields = {
    { consumer = typedefs.no_consumer },
    { protocols = typedefs.protocols_http },
    { consumer_group = typedefs.no_consumer_group },
    { config = {
      type = "record",
      fields = {
        { introspection_url = typedefs.url { required = true } },
        { ttl = { description = "The TTL in seconds for the introspection response. Set to 0 to disable the expiration.", type = "number", default = 30 } },
        { token_type_hint = { description = "The `token_type_hint` value to associate to introspection requests.", type = "string" } },
        { authorization_value = { description = "The value to set as the `Authorization` header when querying the introspection endpoint. This depends on the OAuth 2.0 server, but usually is the `client_id` and `client_secret` as a Base64-encoded Basic Auth string (`Basic MG9hNWl...`).", type = "string", required = true, encrypted = true, referenceable = true, } },
        { timeout = { description = "An optional timeout in milliseconds when sending data to the upstream server.", type = "integer", default = 10000 } },
        { keepalive = { description = "An optional value in milliseconds that defines how long an idle connection lives before being closed.", type = "integer", default = 60000 } },
        { introspect_request = { description = "A boolean indicating whether to forward information about the current downstream request to the introspect endpoint. If true, headers `X-Request-Path` and `X-Request-Http-Method` will be inserted into the introspect request.", type = "boolean", default = false, required = true } },
        { hide_credentials = { description = "An optional boolean value telling the plugin to hide the credential to the upstream API server. It will be removed by Kong before proxying the request.", type = "boolean", default = false } },
        { run_on_preflight = { description = "A boolean value that indicates whether the plugin should run (and try to authenticate) on `OPTIONS` preflight requests. If set to `false`, then `OPTIONS` requests will always be allowed.", type = "boolean", default = true } },
        { anonymous = { description = "An optional string (consumer UUID or username) value to use as an “anonymous” consumer if authentication fails. If empty (default null), the request fails with an authentication failure `4xx`. Note that this value must refer to the consumer `id` or `username` attribute, and **not** its `custom_id`.", type = "string", len_min = 0, default = "" } },
        { consumer_by = { description = "A string indicating whether to associate OAuth2 `username` or `client_id` with the consumer's username. OAuth2 `username` is mapped to a consumer's `username` field, while an OAuth2 `client_id` maps to a consumer's `custom_id`.", type = "string", default = CONSUMER_BY_DEFAULT, one_of = consumer_by_fields, required = true } },
        { custom_introspection_headers = { description = "A list of custom headers to be added in the introspection request.", type = "map", keys = { type = "string" }, values = { type = "string" }, default = {}, required = true } },
        { custom_claims_forward = { description = "A list of custom claims to be forwarded from the introspection response to the upstream request. Claims are forwarded in headers with prefix `X-Credential-{claim-name}`.", type = "set", elements = { type = "string" }, default = {}, required = true } },
      }}
    },
  },
}
