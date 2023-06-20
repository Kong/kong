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
    { entity_type = { description = "The type of the entity for which the counter is maintained.", type = "string", required = true } },
    { count = { description = "The count of entities of the specified type in the workspace.", type = "integer" } },
  }
}
