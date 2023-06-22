-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"
local const = require "kong.enterprise_edition.constants"


---@class kong.plugin.websocket-size-limit.conf
---@field client_max_payload   integer
---@field upstream_max_payload integer


local size = {
  type = "integer",
  between = { 1, const.WEBSOCKET.MAX_PAYLOAD_SIZE },
  required = false,
}


return {
  name = "websocket-size-limit",
  fields = {
    { protocols = typedefs.protocols_ws },
    { consumer_group = typedefs.no_consumer_group },
    { config = {
        type = "record",
        fields = {
          { client_max_payload = size },
          { upstream_max_payload = size },
        },
        entity_checks = {
          { at_least_one_of = { "client_max_payload", "upstream_max_payload" } },
        },
      }
    },
  },
}
