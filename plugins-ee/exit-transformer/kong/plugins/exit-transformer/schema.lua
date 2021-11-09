-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local sandbox = require "kong.tools.sandbox"

local PLUGIN_NAME = require("kong.plugins.exit-transformer").PLUGIN_NAME


local functions_array = {
  type = "array",
  required = true,
  elements = { type = "string", custom_validator = sandbox.validate }
}


return {
  name = PLUGIN_NAME,
  fields = {
    { config = {
      type = "record",
      fields = {
        { functions = functions_array },
        { handle_unknown = { type = "boolean", default = false } },
        { handle_unexpected = { type = "boolean", default = false } },
      }
    } }
  },
}
