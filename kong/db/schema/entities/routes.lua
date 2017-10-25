local typedefs = require "kong.db.schema.typedefs"


return {
  name        = "routes",
  primary_key = { "id" },

  fields = {
    { id             = typedefs.uuid, },
    { created_at     = { type = "integer", timestamp = true, auto = true }, },
    { updated_at     = { type = "integer", timestamp = true, auto = true }, },
    { protocols      = { type = "set", len_min = 1, required = true,
                         elements = typedefs.protocol, }, },
    { methods        = { type = "set",   elements = typedefs.http_method }, },
    { hosts          = { type = "array", elements = { type = "string" } }, },
    { paths          = { type = "array", elements = { type = "string" } }, },
    { regex_priority = { type = "integer", default = 0 }, },
    { strip_path     = { type = "boolean", default = false }, },
    { preserve_host  = { type = "boolean", default = false }, },
    { service        = { type = "foreign", reference = "services", required = true }, },
  },

  entity_checks = {
    { at_least_one_of = {"methods", "hosts", "paths"} },
  },

  dao = "kong.db.dao.routes",
}
