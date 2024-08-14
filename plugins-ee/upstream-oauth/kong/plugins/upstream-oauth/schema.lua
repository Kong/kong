-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cache        = require "kong.plugins.upstream-oauth.cache"
local oauth_client = require "kong.plugins.upstream-oauth.oauth-client"
local redis        = require "kong.enterprise_edition.tools.redis.v2"
local typedefs     = require "kong.db.schema.typedefs"
local ngx          = ngx

local function check_shdict(name)
  if not ngx.shared[name] then
    return false, "missing shared dict '" .. name .. "'"
  end
  return true
end

local function validate_authentication_settings(config)
  if config.client.auth_method ~= oauth_client.constants.AUTH_TYPE_NONE then
    if config.oauth.client_id == ngx.null or config.oauth.client_secret == ngx.null then
      return nil, "client_id and client_secret must be provided for authentication"
    end
  end
  return true
end

local function validate_cache_settings(config)
  if config.cache.strategy == cache.constants.STRATEGY_MEMORY then
    local ok, err = check_shdict(config.cache.memory.dictionary_name)
    if not ok then
      return nil, err
    end
  elseif config.cache.strategy == cache.constants.STRATEGY_REDIS then
    if config.cache.redis.host == ngx.null
        and config.cache.redis.sentinel_nodes == ngx.null
        and config.cache.redis.cluster_nodes == ngx.null then
      return nil, "No redis config provided"
    end
  end
  return true
end

local ALL_ENTITY_CHECKS = {}
for _, validator in ipairs {
  validate_authentication_settings,
  validate_cache_settings
} do
  table.insert(ALL_ENTITY_CHECKS, {
    custom_entity_check = {
      field_sources = { "config" },
      fn = function(entity)
        return validator(entity.config)
      end
    }
  })
end

local schema = {
  name = "upstream-oauth",
  fields = {
    { protocols = typedefs.protocols_http },
    {
      config = {
        type = "record",
        fields = {
          {
            client = {
              type = "record",
              fields = {
                {
                  auth_method = {
                    type     = "string",
                    one_of   = oauth_client.constants.AUTH_TYPES,
                    default  = oauth_client.constants.AUTH_TYPE_CLIENT_SECRET_POST,
                    required = true
                  }
                },
                {
                  client_secret_jwt_alg = {
                    type     = "string",
                    one_of   = oauth_client.constants.CLIENT_SECRET_JWT_ALGS,
                    default  = oauth_client.constants.JWT_ALG_HS512,
                    required = true
                  }
                },
                {
                  http_version = {
                    type             = "number",
                    default          = 1.1,
                    required         = false,
                    custom_validator = function(v)
                      if v == 1.0 or v == 1.1 then
                        return true
                      end
                      return nil, "must be 1.0 or 1.1"
                    end
                  }
                },
                {
                  http_proxy = typedefs.url {
                    required = false
                  }
                },
                {
                  http_proxy_authorization = {
                    type     = "string",
                    required = false
                  }
                },
                {
                  https_proxy = typedefs.url {
                    required = false
                  }
                },
                {
                  https_proxy_authorization = {
                    type     = "string",
                    required = false
                  }
                },
                {
                  no_proxy = {
                    type     = "string",
                    required = false
                  }
                },
                {
                  timeout = typedefs.timeout {
                    default = 10000,
                    required = true
                  }
                },
                {
                  keep_alive = {
                    type = "boolean",
                    default = true,
                    required = true
                  }
                },
                {
                  ssl_verify = {
                    required = false,
                    type     = "boolean",
                    default  = false,
                  }
                },
              }
            }
          },
          {
            oauth = {
              type = "record",
              fields = {
                {
                  token_endpoint = typedefs.url {
                    required = true
                  }
                },
                {
                  token_headers = {
                    type = "map",
                    keys = typedefs.header_name,
                    values = {
                      type = "string",
                      referenceable = true
                    },
                    default = {},
                    required = true
                  }
                },
                {
                  token_post_args = {
                    type = "map",
                    keys = { type = "string" },
                    values = {
                      type = "string",
                      referenceable = true
                    },
                    default = {},
                    required = true
                  }
                },
                {
                  grant_type = {
                    type = "string",
                    one_of = oauth_client.constants.GRANT_TYPES,
                    default = oauth_client.constants.GRANT_TYPE_CLIENT_CREDENTIALS,
                    required = true,
                  }
                },
                {
                  client_id = {
                    type          = "string",
                    encrypted     = true,
                    referenceable = true,
                    required      = false
                  },
                },
                {
                  client_secret = {
                    type          = "string",
                    encrypted     = true,
                    referenceable = true,
                    required      = false
                  },
                },
                {
                  username = {
                    type          = "string",
                    encrypted     = true,
                    referenceable = true,
                    required      = false
                  },
                },
                {
                  password = {
                    type          = "string",
                    encrypted     = true,
                    referenceable = true,
                    required      = false
                  },
                },
                {
                  scopes = {
                    type     = "array",
                    default  = {
                      "openid"
                    },
                    elements = {
                      type = "string"
                    },
                    required = false
                  }
                },
                {
                  audience = {
                    type     = "array",
                    default  = {},
                    elements = {
                      type = "string",
                    },
                    required = false,
                  }
                }
              }
            }
          },
          {
            cache = {
              type = "record",
              fields = {
                {
                  strategy = {
                    type = "string",
                    one_of = cache.constants.STRATEGIES,
                    default = cache.constants.STRATEGY_MEMORY,
                    required = true,
                  }
                },
                {
                  memory = {
                    type = "record",
                    fields = {
                      {
                        dictionary_name = {
                          type = "string",
                          required = true,
                          default = "kong_db_cache",
                        }
                      },
                    },
                  }
                },
                {
                  redis = redis.config_schema
                },
                {
                  eagerly_expire = {
                    type     = "integer",
                    default  = 5,
                    gt       = -1,
                    required = true
                  }
                },
                {
                  default_ttl = {
                    type    = "number",
                    default = 3600,
                    gt      = 0
                  }
                }
              }
            }
          },
          {
            behavior = {
              type = "record",
              fields = {
                {
                  upstream_access_token_header_name = {
                    type = "string",
                    default = "Authorization",
                    required = true,
                    len_min = 0
                  }
                },
                {
                  idp_error_response_status_code = {
                    type = "integer",
                    default = 502,
                    required = true,
                    between = { 500, 599 }
                  }
                },
                {
                  idp_error_response_content_type = {
                    type = "string",
                    default = "application/json; charset=utf-8",
                    required = true,
                    len_min = 0
                  }
                },
                {
                  idp_error_response_message = {
                    type = "string",
                    default = "Failed to authenticate request to upstream",
                    required = true,
                    len_min = 0
                  }
                },
                {
                  idp_error_response_body_template = {
                    type = "string",
                    default = "{ \"code\": \"{{status}}\", \"message\": \"{{message}}\" }",
                    required = true,
                    len_min = 0
                  }
                },
                {
                  purge_token_on_upstream_status_codes = {
                    type = "array",
                    default = { 401 },
                    elements = {
                      type = "integer",
                      between = { 100, 599 }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  },
  entity_checks = ALL_ENTITY_CHECKS,
}

return schema
