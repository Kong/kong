local typedefs = require "kong.db.schema.typedefs"
local utils = require "kong.tools.utils"

return {
  name = "vault_credentials",
  primary_key = { "access_token" },
  generate_admin_api = false,

  fields = {
    { access_token    = { type = "string", auto = true }, },
    { secret_token    = { type = "string", auto = true }, },
    { consumer        = { type = "foreign", reference = "consumers", required = true, } },
    { created_at      = typedefs.auto_timestamp_s },
    { ttl             = { type = "integer", } },
  },
}
