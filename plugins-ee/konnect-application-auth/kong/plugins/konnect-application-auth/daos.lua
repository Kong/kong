-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"

return {
  {
    primary_key = { "id" },
    name = "konnect_applications",
    cache_key = { "client_id" },
    workspaceable = true,
    fields = {
      { id = typedefs.uuid },
      { created_at = typedefs.auto_timestamp_s },
      { client_id = { type = "string", required = true, unique = true, }, },
      { consumer_groups = { default = {}, type = "array", elements = { type = "string" }, }, },
      { scopes = { type = "array", elements = { type = "string", }, }, },
      { auth_strategy_id = { type = "string", required = false }, },
      { tags = typedefs.tags },
    },
  },
}
