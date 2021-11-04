-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"
local null = ngx.null

return {
  name = "application-registration",
  fields = {
    { consumer = typedefs.no_consumer },
    { service = { type = "foreign", reference = "services", ne = null, on_delete = "cascade" }, },
    { route = typedefs.no_route },
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { display_name = { type = "string", unique = true, required = true }, },
          { description = { type = "string", unique = true }, },
          { auto_approve = { type = "boolean", required = true, default = false }, },
          { show_issuer = { type = "boolean", required = true, default = false }, },
        },
      },
    },
  },
}
