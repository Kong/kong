-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"
local ee_typedefs = require "kong.enterprise_edition.db.typedefs"

return {
  name         = "credentials",
  primary_key  = { "id" },
  generate_admin_api = false,
  db_export = false,
  fields = {
    { id              = typedefs.uuid },
    { consumer        = { type = "foreign", reference = "consumers", }, },
    { consumer_type   = ee_typedefs.consumer_type { required = true }},
    { plugin          = { type = "string", required = true }, },
    { credential_data = { type = "string", } },
    { created_at      = typedefs.auto_timestamp_s },
  },
}
