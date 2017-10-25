local typedefs = require "kong.db.schema.typedefs"


return {
  name = "services",
  primary_key = { "id" },

  fields = {
    { id              = typedefs.uuid, },
    { created_at      = { type = "integer", timestamp = true, auto = true }, },
    { updated_at      = { type = "integer", timestamp = true, auto = true }, },
    { name            = { type = "string" }, },
    { retries         = { type = "integer", default = 5, between = { 0, 32767 } }, },
    -- { tags          = { type = "array", array = { type = "string" } }, },
    { protocol        = typedefs.protocol { required = true } },
    { host            = { type = "string" }, },
    { port            = typedefs.port { default = 80 }, },
    { path            = { type = "string" }, },
    { connect_timeout = typedefs.timeout { default = 60000 }, },
    { write_timeout   = typedefs.timeout { default = 60000 }, },
    { read_timeout    = typedefs.timeout { default = 60000 }, },
    -- { load_balancer = { type = "foreign", reference = "load_balancers" } },
  },
}
