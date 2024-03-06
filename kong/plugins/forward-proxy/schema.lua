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
    { protocols = typedefs.protocols_http },
    { consumer_group = typedefs.no_consumer_group },
    { config = {
        type = "record",
        fields = {
          { x_headers = {
            description = "Determines how to handle headers when forwarding the request.",
            type = "string",
            one_of = { "append", "transparent", "delete", },
            required = true,
            default = "append",
          }},

          { http_proxy_host = typedefs.host },
          { http_proxy_port = typedefs.port },
          { https_proxy_host = typedefs.host },
          { https_proxy_port = typedefs.port },

          { proxy_scheme = { description = "The proxy scheme to use when connecting. Only `http` is supported.", type = "string",
            one_of = { "http" },
            required = true,
            default = "http",
          }},
          { auth_username = { description = "The username to authenticate with, if the forward proxy is protected\nby basic authentication.", type = "string",
            required = false,
            referenceable = true,
          }},
          { auth_password = { description = "The password to authenticate with, if the forward proxy is protected\nby basic authentication.", type = "string",
            required = false,
            referenceable = true,
          }},
          { https_verify = { description = "Whether the server certificate will be verified according to the CA certificates specified in lua_ssl_trusted_certificate.", type = "boolean",
            required = true,
            default = false,
          }},
        },

        shorthand_fields = {
          -- deprecated forms, to be removed in Kong 3.0
          { proxy_host = {
              type = "string",
              deprecation = {
                message = "forward-proxy: config.proxy_host is deprecated, please use config.http_proxy_host instead",
                removal_in_version = "4.0", },
              func = function(value)
                return { http_proxy_host = value }
              end,
          }, },
          { proxy_port = {
              type = "integer",
              deprecation = {
                message = "forward-proxy: config.proxy_port is deprecated, please use config.http_proxy_port instead",
                removal_in_version = "4.0", },
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
