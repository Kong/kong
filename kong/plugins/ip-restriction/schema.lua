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
        },
        shorthands = {
          -- deprecated forms, to be removed in Kong 3.0
          { blacklist = function(value)
              return { deny = value }
            end },
          { whitelist = function(value)
              return { allow = value }
            end },
        },
      },
    },
  },
  entity_checks = {
    { at_least_one_of = { "config.allow", "config.deny" }, },
  },
}

