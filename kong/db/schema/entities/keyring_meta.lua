local typedefs = require "kong.db.schema.typedefs"


return {
  name = "keyring_meta",
  generate_admin_api = false,
  primary_key = { "id" },
  dao = "kong.db.dao.keyring_meta",

  fields = {
    { id = { type = "string", required = true } },
    { state = { type = "string", one_of = { "active", "alive", "tombstoned" }, required = true, default = "alive" } },
    { created_at = typedefs.auto_timestamp_s },
  }
}
