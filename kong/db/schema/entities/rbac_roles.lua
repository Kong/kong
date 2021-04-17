-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"

return {
  name = "rbac_roles",
  dao = "kong.db.dao.rbac_roles",
  generate_admin_api = false,
  admin_api_name = "rbac/roles",
  endpoint_key = "name",
  primary_key = { "id" },
  workspaceable = true,
  db_export = false,
  fields = {
    { id             = typedefs.uuid, },
    { name           =  {type = "string", required = true, unique = true}}, -- we accept '@' so it's not a typedef.name
    { comment = {type = "string"} },
    { created_at     = typedefs.auto_timestamp_s },
    { is_default = {type = "boolean", required = true, default = false} },
  }
}
