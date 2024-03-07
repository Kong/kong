-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"

return {
  {
    name = "keyauth_enc_credentials",
    primary_key = { "id" },
    dao = "kong.plugins.key-auth-enc.keyauth_enc_credentials",
    ttl = true,
    endpoint_key = "key",
    workspaceable = true,
    admin_api_name = "key-auths-enc",
    admin_api_nested_name = "key-auth-enc",
    fields = {
      { id = typedefs.uuid },
      { created_at = typedefs.auto_timestamp_s },
      { consumer = { type = "foreign", reference = "consumers", required = true, on_delete = "cascade", }, },
      { key = { type = "string", required = false, unique = true, auto = true, encrypted = true }, },
      { tags = typedefs.tags },
    },
    -- force read_before_write on update
    entity_checks = {},
  },
}
