local typedefs = require "kong.db.schema.typedefs"


return {
  name = "vault-auth",
  fields = {
    { consumer = typedefs.no_consumer },
    { run_on = typedefs.run_on_first },
    { config = {
        type = "record",
        fields = {
          { access_token_name = {
              type = "string",
              required = true,
              elements = typedefs.header_name,
              default = "access_token",
          }, },
          { secret_token_name = {
              type = "string",
              required = true,
              elements = typedefs.header_name,
              default = "secret_token",
          }, },
          { vault = { type = "foreign", reference = "vaults", required = true } },
          { hide_credentials = { type = "boolean", default = false }, },
          { anonymous = { type = "string", uuid = true, legacy = true }, },
          { tokens_in_body = { type = "boolean", default = false }, },
          { run_on_preflight = { type = "boolean", default = true }, },
        },
    }, },
  },
}
