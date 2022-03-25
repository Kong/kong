local typedefs = require "kong.db.schema.typedefs"


return {
  name = "ip-restriction",
  fields = {
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { allow = { type = "array", elements = typedefs.ip_or_cidr, }, },
          { deny = { type = "array", elements = typedefs.ip_or_cidr, }, },
          { status = { type = "number", required = false } },
          { message = { type = "string", required = false } },
        },
      },
    },
  },
  entity_checks = {
    { at_least_one_of = { "config.allow", "config.deny" }, },
  },
}

