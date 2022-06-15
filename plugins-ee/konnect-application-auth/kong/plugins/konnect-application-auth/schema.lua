-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"


local PLUGIN_NAME = "konnect-application-auth"


local AUTH_TYPES = {
  "openid-connect",
  "key-auth",
}


local schema = {
  name = PLUGIN_NAME,
  fields = {
    { consumer = typedefs.no_consumer },
    { route = typedefs.no_route },
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { key_names = {
            type = "array",
            required = true,
            elements = typedefs.header_name,
            default = { "apikey" },
        }, },
          { auth_type = { required = true, type = "string", one_of = AUTH_TYPES, default = "openid-connect", } },
          { scope = { required = true, type = "string", unique = true } },
        },
        entity_checks = {},
      },
    },
  },
}

return schema
