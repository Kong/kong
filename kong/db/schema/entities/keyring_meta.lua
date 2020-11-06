-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"


return {
  name = "keyring_meta",
  generate_admin_api = false,
  primary_key = { "id" },
  dao = "kong.db.dao.keyring_meta",

  fields = {
    { id = { type = "string", required = true } },
    { state = { type = "string", one_of = { "active", "alive", "tombstoned" }, required = true, default = "alive" } },
    { created_at = typedefs.auto_timestamp_s },
  }
}
