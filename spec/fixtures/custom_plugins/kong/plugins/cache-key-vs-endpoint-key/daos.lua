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
