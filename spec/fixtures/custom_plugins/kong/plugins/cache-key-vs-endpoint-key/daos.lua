-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"


return {
  {
    name = "ck_vs_ek_testcase",
    primary_key = { "id" },
    endpoint_key = "name",
    cache_key = { "route", "service" },
    fields = {
      { id = typedefs.uuid },
      { name = typedefs.utf8_name }, -- this typedef declares 'unique = true'
      { service = { type = "foreign", reference = "services", on_delete = "cascade",
                    default = ngx.null, unique = true }, },
      { route   = { type = "foreign", reference = "routes", on_delete = "cascade",
                    default = ngx.null, unique = true }, },
    },
    entity_checks = {
      { mutually_exclusive = {
          "service",
          "route",
        }
      },
      { at_least_one_of = {
          "service",
          "route",
        }
      }
    }
  }
}
