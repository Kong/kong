local typedefs = require "kong.db.schema.typedefs"


return {
  name = "acl",
  fields = {
    { consumer = typedefs.no_consumer },
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { allow = { description = "Arbitrary group names that are allowed to consume the service or route. One of `config.allow` or `config.deny` must be specified.",
              type = "array",
              elements = { type = "string" }, }, },
          { deny = { description = "Arbitrary group names that are not allowed to consume the service or route. One of `config.allow` or `config.deny` must be specified.",
              type = "array",
              elements = { type = "string" }, }, },
          { hide_groups_header = { type = "boolean", required = true, default = false, description = "If enabled (`true`), prevents the `X-Consumer-Groups` header from being sent in the request to the upstream service." }, },
        },
      }
    }
  },
  entity_checks = {
    { only_one_of = { "config.allow", "config.deny" }, },
    { at_least_one_of = { "config.allow", "config.deny" }, },
  },
}
