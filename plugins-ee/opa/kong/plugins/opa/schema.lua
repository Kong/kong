-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"

local schema = {
  name = "opa",
  fields = {
    { consumer = typedefs.no_consumer },
    { protocols = typedefs.protocols_http },
    { consumer_group = typedefs.no_consumer_group },
    { config = {
        type = "record",
        fields = {
          {
            opa_protocol = { description = "The protocol to use when talking to Open Policy Agent (OPA) server. Allowed protocols are `http` and `https`.", type = "string", default = "http", one_of = { "http", "https" }, },
          },
          {
            opa_host = typedefs.host{ required = true, default = "localhost" },
          },
          {
            opa_port = typedefs.port{ required =true, default = 8181 },
          },
          {
            opa_path =  typedefs.path{ required = true },
          },
          {
            include_service_in_opa_input = { description = "If set to true, the Kong Gateway Service object in use for the current request is included as input to OPA.", type = "boolean", default = false },
          },
          {
            include_route_in_opa_input = { description = "If set to true, the Kong Gateway Route object in use for the current request is included as input to OPA.", type = "boolean", default = false },
          },
          {
            include_consumer_in_opa_input = { description = "If set to true, the Kong Gateway Consumer object in use for the current request (if any) is included as input to OPA.", type = "boolean", default = false },
          },
          {
            include_body_in_opa_input = { type = "boolean", default = false },
          },
          {
            include_parsed_json_body_in_opa_input = { description = "If set to true and the `Content-Type` header of the current request is `application/json`, the request body will be JSON decoded and the decoded struct is included as input to OPA.", type = "boolean", default = false },
          },
          {
            include_uri_captures_in_opa_input = { description = "If set to true, the regex capture groups captured on the Kong Gateway Route's path field in the current request (if any) are included as input to OPA.", type = "boolean", default = false },
          },
          {
            ssl_verify = { description = "If set to true, the OPA certificate will be verified according to the CA certificates specified in lua_ssl_trusted_certificate.", type = "boolean", required = true, default = true, },
          },
        },
      },
    },
  },
}

return schema
