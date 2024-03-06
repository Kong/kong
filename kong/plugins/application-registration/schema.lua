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
    { consumer_group = typedefs.no_consumer_group },
    { config = {
        type = "record",
        fields = {
          { display_name = { description = "Unique display name used for a Service in the Developer Portal.", type = "string", unique = true, required = true }, },
          { description = { description = "Unique description displayed in information about a Service in the Developer Portal.", type = "string", unique = true }, },
          { auto_approve = { description = "If enabled, all new Service Contracts requests are automatically approved.", type = "boolean", required = true, default = false }, },
          { show_issuer = { description = "Displays the **Issuer URL** in the **Service Details** dialog.", type = "boolean", required = true, default = false }, },
        },
      },
    },
  },
}
