local typedefs = require "kong.db.schema.typedefs"
local Schema = require "kong.db.schema"

local application_instances_status = Schema.define { type = "integer", between = { 0, 5 }, default = 5 }


return {
  name          = "application_instances",
  primary_key   = { "id" },
  workspaceable = true,
  dao           = "kong.db.dao.application_instances",
  generate_admin_api = false,

  fields = {
    { id             = typedefs.uuid, },
    { created_at     = typedefs.auto_timestamp_s },
    { updated_at     = typedefs.auto_timestamp_s },
    { application    = { type = "foreign", reference = "applications", required = true }, },
    { service        = { type = "foreign", reference = "services", required = true }, },
    { suspended      = { type = "boolean", default = false } },
    { composite_id   = { type = "string", unique = true }, },
    { status         = application_instances_status },
  },
}
