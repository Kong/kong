-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"

return {
  name = "rbac_role_entities",
  generate_admin_api = false,
  admin_api_nested_name = "entities",
  primary_key = { "role", "entity_id" },
  db_export = false,
  fields = {
    { role = { type = "foreign", required = true, reference = "rbac_roles", on_delete = "cascade" } },
    { entity_id = {type = "string", required = true,} },
    { entity_type = {type = "string", required = true} },
    { actions = {type = "integer", required = true,} },
    { negative = {type = "boolean", required = true, default = false,} },
    { comment = {type = "string",} },
    { created_at  = typedefs.auto_timestamp_s },
  },
}
