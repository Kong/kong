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
          { always_use_authenticated_groups = { type = "boolean", required = true, default = false, description = "If enabled (`true`), the authenticated groups will always be used even when an authenticated consumer already exists. If the authenticated groups don't exist, it will fallback to use the groups associated with the consumer. By default the authenticated groups will only be used when there is no consumer or the consumer is anonymous." } },
        },
      }
    }
  },
  entity_checks = {
    { only_one_of = { "config.allow", "config.deny" }, },
    { at_least_one_of = { "config.allow", "config.deny" }, },
  },
}
