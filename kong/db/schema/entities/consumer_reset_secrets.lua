-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"

return {
  name = "consumer_reset_secrets",
  generate_admin_api = false,

  primary_key = { "id" },
  db_export = false,

  fields = {
    { id = typedefs.uuid, },
    { created_at = typedefs.auto_timestamp_s, },
    { updated_at = typedefs.auto_timestamp_s, },
    { consumer = { description = "The consumer associated with the secret", type = "foreign", reference = "consumers", on_delete = "cascade", required = true, }, },
    { secret = { description = "The secret value", type = "string", auto = true, required = true, }, },
    { status = { description = "The status of the reset.", type = "integer", default = 1, between = { 1, 3 }, required = true, }, },
    { client_addr = { description = "The client address associated with the reset secret.", type = "string", required = true, } },
  },
}
