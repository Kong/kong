-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"


return {
  name = "vault-auth",
  fields = {
    { consumer = typedefs.no_consumer },
    { config = {
        type = "record",
        fields = {
          { access_token_name = {
              type = "string",
              required = true,
              elements = typedefs.header_name,
              default = "access_token",
          }, },
          { secret_token_name = {
              type = "string",
              required = true,
              elements = typedefs.header_name,
              default = "secret_token",
          }, },
          { vault = { type = "foreign", reference = "vaults", required = true } },
          { hide_credentials = { type = "boolean", default = false }, },
          { anonymous = { type = "string", uuid = true, legacy = true }, },
          { tokens_in_body = { type = "boolean", default = false }, },
          { run_on_preflight = { type = "boolean", default = true }, },
        },
    }, },
  },
}
