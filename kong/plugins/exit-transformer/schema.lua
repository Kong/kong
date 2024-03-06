-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local sandbox = require "kong.tools.sandbox"
local typedefs = require "kong.db.schema.typedefs"

local PLUGIN_NAME = require("kong.plugins.exit-transformer").PLUGIN_NAME


local functions_array = {
  type = "array",
  required = true,
  elements = { type = "string", custom_validator = sandbox.validate }
}


return {
  name = PLUGIN_NAME,
  fields = {
    { protocols = typedefs.protocols_http },
    { consumer_group = typedefs.no_consumer_group },
    { config = {
      type = "record",
      fields = {
        { functions = functions_array },
        { handle_unknown = { description = "Determines whether to handle unknown status codes by transforming their responses.", type = "boolean", default = false } },
        { handle_unexpected = { description = "Determines whether to handle unexpected errors by transforming their responses.", type = "boolean", default = false } },
      }
    } }
  },
}
