local typedefs = require "kong.db.schema.typedefs"

return {
  name = "consumer_reset_secrets",
  generate_admin_api = false,

  primary_key = { "id" },

  fields = {
    { id = typedefs.uuid, },
    { created_at = typedefs.auto_timestamp_s, },
    { updated_at = typedefs.auto_timestamp_s, },
    { consumer = { type = "foreign", reference = "consumers", on_delete = "cascade", required = true, }, },
    { secret = { type = "string", auto = true, required = true, }, },
    { status = { type = "integer", default = 1, between = { 1, 3 }, required = true, }, },
    { client_addr = { type = "string", required = true, } },
  },
}
