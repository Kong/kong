-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"


return {
  name          = "applications",
  primary_key   = { "id" },
  workspaceable = true,
  dao           = "kong.db.dao.applications",
  db_export     = false,

  fields = {
    { id             = typedefs.uuid, },
    { created_at     = typedefs.auto_timestamp_s },
    { updated_at     = typedefs.auto_timestamp_s },
    { redirect_uri   = typedefs.url },
    { custom_id      = { description = "The custom ID of the application (unique identifier).", type = "string", unique = true } },
    { name           = { description = "The name of the application.", type = "string", required = true } },
    { description    = { description = "The description of the application.", type = "string" } },
    { consumer       = { description = "The foreign key referencing the associated consumer.", type = "foreign", reference = "consumers", required = true } },
    { developer      = { description = "The foreign key referencing the associated developer.", type = "foreign", reference = "developers", required = true } },
    { meta           = { description = "Additional metadata associated with the application.", type = "string" } },
  },
}

