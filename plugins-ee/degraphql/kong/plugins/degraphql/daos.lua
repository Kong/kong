-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"

return {
  {
    name = "degraphql_routes",
    primary_key = { "id" },
    endpoint_key = "id",
    -- cache_key = { "service", "method", "uri" },
    fields = {
      { id = typedefs.uuid },
      { service = { type = "foreign", reference = "services" } },
      { methods = { type = "set", elements = typedefs.http_method,
                    default = { "GET" } } },
      { uri = { type = "string", required = true } },
      { query = { type = "string", required = true } },
      { created_at = typedefs.auto_timestamp_s },
      { updated_at = typedefs.auto_timestamp_s },
    }
  },
}
