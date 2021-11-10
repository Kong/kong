-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"
local utils = require "kong.tools.utils"

return {
  name = "vault_credentials",
  primary_key = { "access_token" },
  generate_admin_api = false,

  fields = {
    { access_token    = { type = "string", auto = true }, },
    { secret_token    = { type = "string", auto = true }, },
    { consumer        = { type = "foreign", reference = "consumers", required = true, on_delete = ngx.null } },
    { created_at      = typedefs.auto_timestamp_s },
    { ttl             = { type = "integer", } },
  },
}
