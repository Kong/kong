-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

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
        shorthand_fields = {
          -- deprecated forms, to be removed in Kong 3.0
          { blacklist = {
              type = "array",
              elements = { type = "string", is_regex = true },
              func = function(value)
                return { deny = value }
              end,
          }, },
          { whitelist = {
              type = "array",
              elements = { type = "string", is_regex = true },
              func = function(value)
                return { allow = value }
              end,
          }, },
        },
      },
    },
  },
  entity_checks = {
    { at_least_one_of = { "config.allow", "config.deny" }, },
  },
}

