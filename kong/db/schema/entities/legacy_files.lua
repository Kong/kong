-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"
local Schema = require "kong.db.schema"


local type = Schema.define {
  type = "string",
  one_of = {
    "page",
    "partial",
    "spec",
  }
}


return {
  name = "legacy_files",
  primary_key = { "id" },
  workspaceable = true,
  endpoint_key = "name",
  generate_admin_api = false,
  db_export = false,

  fields = {
    { id         = typedefs.uuid, },
    { created_at = typedefs.auto_timestamp_s },
    { type       = type },
    { name       = { type = "string", required = true, unique = true } },
    { auth       = { type = "boolean", default = true } },
    { contents   = { type = "string", len_min = 0, required = true } },
  }
}
