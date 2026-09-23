local typedefs = require "kong.db.schema.typedefs"
local constants = require "kong.constants"

return {
  name = "workspaces",
  primary_key = { "id" },
  cache_key = { "name" },
  endpoint_key = "name",
  dao          = "kong.db.dao.workspaces",
  generate_admin_api = false,

  fields = {
    { id          = typedefs.uuid },
    { name        = typedefs.utf8_name { required = true, not_one_of = { table.unpack(constants.CORE_ENTITIES) }, } },
    { comment     = { type = "string" } },
    { created_at  = typedefs.auto_timestamp_s },
    { updated_at  = typedefs.auto_timestamp_s },
    { meta        = { type = "record", fields = {} } },
    { config      = { type = "record", fields = {} } },
  }
}
