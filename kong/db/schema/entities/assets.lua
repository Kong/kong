local typedefs = require "kong.db.schema.typedefs"

return {
  name         = "assets",
  primary_key  = { "id" },
  endpoint_key = "name",
  dao          = "kong.db.dao.assets",

  workspaceable = true,

  fields = {
    { id           = typedefs.uuid, },
    { name         = { description = "The name of the assets.", type = "string", required = true } },
    { created_at   = typedefs.auto_timestamp_s },
    { updated_at   = typedefs.auto_timestamp_s },
    { tags         = typedefs.tags },
    { url          = { description = "The URL of assets ", type = "string", required = true } },
    { metadata     = { description = "The metadata of this assets.", type = "record", 
      fields = {
        { sha256sum = { description = "Checksum of the artifacts in SHA256", type = "string" } },
        { type = { description = "Type of the artifact", type = "string" } },
        { size = { description = "Size of the artifact", type = "number" } },
      },}, },
  },

}
