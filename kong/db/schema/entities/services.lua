local typedefs = require "kong.db.schema.typedefs"
local Schema   = require("kong.db.schema")


local nonzero_timeout = Schema.define {
  type = "integer",
  between = { 1, math.pow(2, 31) - 2 },
}


return {
  name = "services",
  primary_key = { "id" },
  endpoint_key = "name",

  fields = {
    { id              = typedefs.uuid, },
    { created_at      = typedefs.auto_timestamp_s },
    { updated_at      = typedefs.auto_timestamp_s },
    { name            = typedefs.name },
    { retries         = { type = "integer", default = 5, between = { 0, 32767 } }, },
    -- { tags          = { type = "array", array = { type = "string" } }, },
    { protocol        = typedefs.protocol { required = true, default = "http" } },
    { host            = typedefs.host { required = true } },
    { port            = typedefs.port { required = true, default = 80 }, },
    { path            = typedefs.path },
    { connect_timeout = nonzero_timeout { default = 60000 }, },
    { write_timeout   = nonzero_timeout { default = 60000 }, },
    { read_timeout    = nonzero_timeout { default = 60000 }, },
    -- { load_balancer = { type = "foreign", reference = "load_balancers" } },
  },

  entity_checks = {
    { conditional = { if_field = "protocol",
                      if_match = { one_of = { "tcp", "tls" }},
                      then_field = "path",
                      then_match = { eq = ngx.null }}},
  },
}
