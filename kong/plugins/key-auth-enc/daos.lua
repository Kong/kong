local typedefs = require "kong.db.schema.typedefs"

return {
  keyauth_credentials = {
    primary_key = { "id" },
    dao = "kong.plugins.key-auth-enc.keyauth_enc_credentials",
    name = "keyauth_enc_credentials",
    endpoint_key = "key",
    workspaceable = true,
    admin_api_name = "key-auths-enc",
    admin_api_nested_name = "key-auth-enc",
    fields = {
      { id = typedefs.uuid },
      { created_at = typedefs.auto_timestamp_s },
      { consumer = { type = "foreign", reference = "consumers", required = true, on_delete = "cascade", }, },
      { key = { type = "string", required = false, unique = true, auto = true, encrypted = true }, },
    },
    -- force read_before_write on update
    entity_checks = {},
  },
}
