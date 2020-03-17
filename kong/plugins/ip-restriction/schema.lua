local typedefs = require "kong.db.schema.typedefs"


return {
  name = "ip-restriction",
  fields = {
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { whitelist = { type = "array", elements = typedefs.ip_or_cidr, }, },
          { blacklist = { type = "array", elements = typedefs.ip_or_cidr, }, },
        },
      },
    },
  },
  entity_checks = {
    { at_least_one_of = { "config.whitelist", "config.blacklist" }, },
  },
}

