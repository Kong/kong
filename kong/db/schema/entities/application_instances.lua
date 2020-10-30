-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"
local Schema = require "kong.db.schema"

local application_instances_status = Schema.define { type = "integer", between = { 0, 5 }, default = 5 }


return {
  name          = "application_instances",
  primary_key   = { "id" },
  workspaceable = true,
  dao           = "kong.db.dao.application_instances",
  generate_admin_api = false,
  db_export = false,

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
