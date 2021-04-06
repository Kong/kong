local typedefs = require "kong.db.schema.typedefs"


return {
  name = "jwt",
  fields = {
    { consumer = typedefs.no_consumer },
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { uri_param_names = {
              type = "set",
              elements = { type = "string" },
              default = { "jwt" },
          }, },
          { cookie_names = {
              type = "set",
              elements = { type = "string" },
              default = {}
          }, },
          { key_claim_name = { type = "string", default = "iss" }, },
          { secret_is_base64 = { type = "boolean", required = true, default = false }, },
          { claims_to_verify = {
              type = "set",
              elements = {
                type = "string",
                one_of = { "exp", "nbf" },
          }, }, },
          { scopes_claim = { type = "string", default = "scope" }, },
          { scopes_required = {
            type = "set",
            elements = { type = "string" },
            default = {}
          }, },
          { claims_headers =  {
            type = "array",
            default = {
              "iss:x-jwt-iss",
              "sub:x-jwt-sub",
              "scope:x-jwt-scope",
              "_validated_scope:x-jwt-validated-scope"
            },
            required = true,
            elements = { type = "string", match = "^[^:]+:.*$" },
          }, },
          { anonymous = { type = "string" }, },
          { run_on_preflight = { type = "boolean", required = true, default = true }, },
          { maximum_expiration = {
            type = "number",
            default = 0,
            between = { 0, 31536000 },
          }, },
          { header_names = {
            type = "set",
            elements = { type = "string" },
            default = { "authorization" },
          }, },
        },
      },
    },
  },
  entity_checks = {
    { conditional = {
        if_field = "config.maximum_expiration",
        if_match = { gt = 0 },
        then_field = "config.claims_to_verify",
        then_match = { contains = "exp" },
    }, },
  },
}
