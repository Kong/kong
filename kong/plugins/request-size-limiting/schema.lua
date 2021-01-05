-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"
local handler = require "kong.plugins.request-size-limiting.handler"


local size_units = handler.size_units


return {
  name = "request-size-limiting",
  fields = {
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { allowed_payload_size = { type = "integer", default = 128 }, },
          { size_unit = { type = "string", required = true, default = size_units[1], one_of = size_units }, },
          { require_content_length = { type = "boolean", default = false }, },
        },
      },
    },
  },
}
