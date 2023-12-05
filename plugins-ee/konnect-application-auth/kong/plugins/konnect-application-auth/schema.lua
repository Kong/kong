-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"

local openid_schema = require "kong.plugins.openid-connect.schema"
local openid_fields

-- getting the config field of openid-connect plugin schema
for _, field in pairs(openid_schema.fields) do
  if field.config then
    openid_fields = field.config.fields
    break
  end
end

assert(openid_fields ~= nil, "OIDC config fields not found")

local PLUGIN_NAME = "konnect-application-auth"


local AUTH_TYPES = {
  "openid-connect",
  "key-auth",
  "v2-strategies",
}

local key_names_field_schema = {
  key_names = {
    description = "The names of the headers containing the API key. You can specify multiple header names.",
    type = "array",
    required = true,
    elements = typedefs.header_name,
    default = { "apikey" },
  },
}

local strategy_id_schema = {
  strategy_id = {
    type = "string",
    description = "The strategy id the config is tied to.",
    required = true
  }
}

local strategy_field_schema = {
  {
    key_auth = {
      type = "array",
      description = "List of key_auth strategies.",
      required = false,
      elements = {
        type = "record",
        fields = {
          strategy_id_schema,
          {
            config = {
              type = "record",
              required = true,
              fields = {
                key_names_field_schema,
              }
            }
          }
        }
      }
    }
  },
  {
    openid_connect = {
      type = "array",
      description = "List of openid_connect strategies.",
      required = false,
      elements = {
        type = "record",
        fields = {
          strategy_id_schema,
          {
            config = {
              type = "record",
              description = "openid-connect plugin configuration.",
              fields = openid_fields
            }
          }
        }
      }
    }
  },
}


local schema = {
  name = PLUGIN_NAME,
  fields = {
    { consumer = typedefs.no_consumer },
    { route = typedefs.no_route },
    { protocols = typedefs.protocols_http },
    { consumer_group = typedefs.no_consumer_group },
    {
      config = {
        type = "record",
        fields = {
          key_names_field_schema,
          {
            auth_type = {
              description = "The type of authentication to be performed. Possible values are: 'openid-connect', 'key-auth', 'v2-strategies'.",
              required = true,
              type = "string",
              one_of = AUTH_TYPES,
              default = "openid-connect",
            },
          },
          { scope = { description = "The unique scope identifier for the plugin configuration.", required = true, type = "string", unique = true } },
          {
            v2_strategies = {
              type = "record",
              description = "The map of v2 strategies.",
              required = false,
              default = {},
              fields = strategy_field_schema,
            }
          }
        },
        entity_checks = {},
      },
    },
  },
}
return schema
