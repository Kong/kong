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
          { http_proxy_host = typedefs.host },
          { http_proxy_port = typedefs.port },
          { https_proxy_host = typedefs.host },
          { https_proxy_port = typedefs.port },

          { proxy_scheme = {
            type = "string",
            one_of = { "http" },
            required = true,
            default = "http",
          }},
          { auth_username = {
            type = "string",
            required = false,
            referenceable = true,
          }},
          { auth_password = {
            type = "string",
            required = false,
            referenceable = true,
          }},
          { https_verify = {
            type = "boolean",
            required = true,
            default = false,
          }},
        },

        shorthand_fields = {
          -- deprecated forms, to be removed in Kong 3.0
          { proxy_host = {
              type = "string",
              func = function(value)
                return { http_proxy_host = value }
              end,
          }, },
          { proxy_port = {
              type = "integer",
              func = function(value)
                return { http_proxy_port = value }
              end,
          }, },
        },

        entity_checks = {
          { at_least_one_of = { "http_proxy_host", "https_proxy_host" } },
          { at_least_one_of = { "http_proxy_port", "https_proxy_port" } },

          { mutually_required = { "http_proxy_host", "http_proxy_port" } },
          { mutually_required = { "https_proxy_host", "https_proxy_port" } },
        }
      }
    }
  }
}
