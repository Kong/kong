local typedefs = require "kong.db.schema.typedefs"


return {
  name = "ip-restriction",
  fields = {
    { run_on = typedefs.run_on_first },
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { whitelist = { type = "array", elements = typedefs.cidr, }, },
          { blacklist = { type = "array", elements = typedefs.cidr, }, },
        },
      },
    },
  },
  entity_checks = {
    { only_one_of = { "config.whitelist", "config.blacklist" }, },
    { at_least_one_of = { "config.whitelist", "config.blacklist" }, },
  },
}
