local typedefs = require "kong.db.schema.typedefs"


return {
  vaults = {
    primary_key = { "id" },
    name = "vaults",
    endpoint_key = "name",
  
    fields = {
      { id            = typedefs.uuid, },
      { created_at    = typedefs.auto_timestamp_s, },
      { updated_at    = typedefs.auto_timestamp_s, },
      { name          = typedefs.name, },
      { protocol      = { type    = "string",
                          one_of  = { "http", "https" },
                          default = "http",
                        }, },
      { host          = typedefs.host { required = true } },
      { port          = typedefs.port { required = true, default = 8200, }, },
      { mount         = { type = "string", required = true, }, },
      { vault_token   = { type = "string", required = true, }, },
    },
  }
}
