local typedefs = require "kong.db.schema.typedefs"


return {
  basicauth_credentials = {
    dao = "kong.plugins.basic-auth.basicauth_credentials",
    name = "basicauth_credentials",
    primary_key = { "id" },
    cache_key = { "username" },
    endpoint_key = "username",
    -- Passwords are hashed on insertion, so the exported passwords would be encrypted.
    -- Importing them back would require "plain" unencrypted passwords instead
    db_export = false,
    admin_api_name = "basic-auths",
    admin_api_nested_name = "basic-auth",
    fields = {
      { id = typedefs.uuid },
      { created_at = typedefs.auto_timestamp_s },
      { consumer = { type = "foreign", reference = "consumers", required = true, on_delete = "cascade", }, },
      { username = { type = "string", required = true, unique = true }, },
      { password = { type = "string", required = true }, },
      { tags     = typedefs.tags },
    },
  },
}
