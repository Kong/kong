local typedefs = require "kong.db.schema.typedefs"

return {
  name         = "snis",
  primary_key  = { "id" },
  endpoint_key = "name",
  dao          = "kong.db.dao.snis",

  workspaceable = true,

  fields = {
    { id           = typedefs.uuid, },
    { name         = typedefs.wildcard_host { required = true, unique = true, unique_across_ws = true }},
    { created_at   = typedefs.auto_timestamp_s },
    { tags         = typedefs.tags },
    { certificate  = { type = "foreign", reference = "certificates", required = true }, },
  },

}
