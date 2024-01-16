-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local typedefs = require "kong.db.schema.typedefs"


return {
  name = "hcv",
  fields = {
    {
      config = {
        type = "record",
        fields = {
          { protocol            = { type = "string", one_of = { "http", "https" }, default = "http" } },
          { host                = typedefs.host { required = true, default = "127.0.0.1" } },
          { port                = typedefs.port { required = true, default = 8200 } },
          { namespace           = { type = "string", required = false } },
          { mount               = { type = "string", required = true, default = "secret" } },
          { kv                  = { type = "string", one_of = { "v1", "v2" }, default = "v1" } },
          { auth_method         = { type = "string", one_of = { "token", "kubernetes", "approle" }, default = "token" }},
          -- Token Auth
          { token               = { type = "string", required = false, encrypted = true }},
          -- Kubernetes Auth
          { kube_role           = { type = "string", required = false }},
          { kube_auth_path      = { type = "string", required = true, default = "kubernetes" } },
          { kube_api_token_file = { type = "string", required = false }},
          -- AppRole Auth
          { approle_auth_path = { type = "string", required = true, default = "approle" } },
          { approle_role_id     = { type = "string", required = false }},
          { approle_secret_id   = { type = "string", required = false }},
          { approle_secret_id_file = { type = "string", required = false }},
          { approle_response_wrapping = { type = "boolean", required = true, default = false }},
          -- TTL settings
          { ttl                 = typedefs.ttl },
          { neg_ttl             = typedefs.ttl },
          { resurrect_ttl       = typedefs.ttl },
        },
        entity_checks = {
          {
            conditional = {
              if_field = "auth_method", if_match = { eq = "token" },
              then_field = "token", then_match = { required = true },
            },
          },
          {
            conditional = {
              if_field = "auth_method", if_match = { eq = "kubernetes" },
              then_field = "token", then_match = { eq = ngx.null },
            },
          },
          {
            conditional = {
              if_field = "auth_method", if_match = { eq = "approle" },
              then_field = "approle_role_id", then_match = { required = true },
            },
          },
        },
      },
    },
  },
}
