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
    endpoint_key = "session_id",
    name = "sessions",
    cache_key = { "session_id" },
    ttl = true,
    db_export = false,
    fields = {
      { id = typedefs.uuid },
      { session_id = { type = "string", unique = true, required = true } },
      { expires = { type = "integer" } },
      { data = { type = "string" } },
      { created_at = typedefs.auto_timestamp_s },
    }
  }
}
