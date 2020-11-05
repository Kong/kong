-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs        = require "kong.db.schema.typedefs"


return {
  name = "forward-proxy",
  fields = {
    { config = {
        type = "record",
        fields = {
          { proxy_host = typedefs.host {required = true} },
          { proxy_port = typedefs.port {required = true} },
          { proxy_scheme = {
            type = "string",
            one_of = { "http" },
            required = true,
            default = "http",
          }},
          { https_verify = {
            type = "boolean",
            required = true,
            default = false,
          }},
        }
      }
    }
  }
}
