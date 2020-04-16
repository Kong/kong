local typedefs = require "kong.db.schema.typedefs"
local crypto = require "kong.plugins.basic-auth.crypto"


return {
  basicauth_credentials = {
    name = "basicauth_credentials",
    primary_key = { "id" },
    cache_key = { "username" },
    endpoint_key = "username",
    admin_api_name = "basic-auths",
    admin_api_nested_name = "basic-auth",
    fields = {
      { id = typedefs.uuid },
      { created_at = typedefs.auto_timestamp_s },
      { consumer = { type = "foreign", reference = "consumers", required = true, on_delete = "cascade" }, },
      { username = { type = "string", required = true, unique = true }, },
      { password = { type = "string", required = true, export_as = "encrypted_password" }, },
      { tags     = typedefs.tags },
    },
    shorthands = {
      {
        encrypted_password = function(encrypted_password)
          return { password = encrypted_password }
        end
      }
    },
    transformations = {
      { -- First transformation
        input = { "password" },
        needs = { "consumer.id" },
        on_write = function(password, consumer_id)
          return { password = crypto.hash(consumer_id, password) }
        end,
      },
      { -- The following transformation needs to be declared after password encryption
        -- The first transformation encrypts them password, and this one overrides
        -- the encryption if an "encrypted password" was found
        input = { "encrypted_password" },
        on_write = function(encrypted_password)
          return { password = encrypted_password }
        end,
      },
    },
  },
}
