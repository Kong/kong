local typedefs = require "kong.db.schema.typedefs"


return {
  name = "acl",
  fields = {
    { consumer = typedefs.no_consumer },
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { allow = { type = "array", elements = { type = "string" }, }, },
          { deny = { type = "array", elements = { type = "string" }, }, },
          { hide_groups_header = { type = "boolean", default = false }, },
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
      }
    }
  },
  entity_checks = {
    { only_one_of = { "config.allow", "config.deny" }, },
    { at_least_one_of = { "config.allow", "config.deny" }, },
  },
}
