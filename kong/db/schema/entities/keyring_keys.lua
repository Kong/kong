-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"


return {
  name = "keyring_keys",
  generate_admin_api = false,
  primary_key = { "id" },

  fields = {
    { id = { description = "The key ID.", type = "string", required = true } },
    { recovery_key_id = { description = "The ID of the recovery key.", type = "string", required = true } },
    { key_encrypted = { description = "A string representing an encrypted key.", type = "string", required = true } },
    { created_at = typedefs.auto_timestamp_s },
    { updated_at = typedefs.auto_timestamp_s },
  }
}
