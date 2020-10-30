-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"


return {
  name = "workspace_entity_counters",
  primary_key = { "workspace_id", "entity_type"},
  generate_admin_api = false,
  db_export = false,

  fields = {
    { workspace_id = typedefs.uuid },
    { entity_type = { type = "string", required = true } },
    { count = { type = "integer" } },
  }
}
