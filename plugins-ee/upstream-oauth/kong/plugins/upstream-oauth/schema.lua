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
                    description = "The authentication method used in client requests to the IdP. Supported values are: `client_secret_basic` to send `client_id` and `client_secret` in the `Authorization: Basic` header, `client_secret_post` to send `client_id` and `client_secret` as part of the request body, or `client_secret_jwt` to send a JWT signed with the `client_secret` using the client assertion as part of the body.",
                    type     = "string",
                    one_of   = oauth_client.constants.AUTH_TYPES,
                    default  = oauth_client.constants.AUTH_TYPE_CLIENT_SECRET_POST,
                    required = true
                  }
                },
                {
                  client_secret_jwt_alg = {
                    description = "The algorithm to use with JWT when using `client_secret_jwt` authentication.",
                    type     = "string",
                    one_of   = oauth_client.constants.CLIENT_SECRET_JWT_ALGS,
                    default  = oauth_client.constants.JWT_ALG_HS512,
                    required = true
                  }
                },
                {
                  http_version = {
                    description = "The HTTP version used for requests made by this plugin. Supported values: `1.1` for HTTP 1.1 and `1.0` for HTTP 1.0.",
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
                    description = "The proxy to use when making HTTP requests to the IdP.",
                    required = false
                  }
                },
                {
                  http_proxy_authorization = {
                    description = "The `Proxy-Authorization` header value to be used with `http_proxy`.",
                    type     = "string",
                    required = false
                  }
                },
                {
                  https_proxy = typedefs.url {
                    description = "The proxy to use when making HTTPS requests to the IdP.",
                    required = false
                  }
                },
                {
                  https_proxy_authorization = {
                    description = "The `Proxy-Authorization` header value to be used with `https_proxy`.",
                    type     = "string",
                    required = false
                  }
                },
                {
                  no_proxy = {
                    description = "A comma-separated list of hosts that should not be proxied.",
                    type     = "string",
                    required = false
                  }
                },
                {
                  timeout = typedefs.timeout {
                    description = "Network I/O timeout for requests to the IdP in milliseconds.",
                    default = 10000,
                    required = true
                  }
                },
                {
                  keep_alive = {
                    description = "Whether to use keepalive connections to the IdP.",
                    type = "boolean",
                    default = true,
                    required = true
                  }
                },
                {
                  ssl_verify = {
                    description = "Whether to verify the certificate presented by the IdP when using HTTPS.",
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
                    description = "The token endpoint URI.",
                    required = true
                  }
                },
                {
                  token_headers = {
                    description = "Extra headers to be passed in the token endpoint request.",
                    type = "map",
                    keys = typedefs.header_name,
                    values = {
                      type = "string",
                      referenceable = true
                    },
                  }
                },
                {
                  token_post_args = {
                    description = "Extra post arguments to be passed in the token endpoint request.",
                    type = "map",
                    keys = { type = "string" },
                    values = {
                      type = "string",
                      referenceable = true
                    },
                  }
                },
                {
                  grant_type = {
                    description = "The OAuth grant type to be used.",
                    type = "string",
                    one_of = oauth_client.constants.GRANT_TYPES,
                    default = oauth_client.constants.GRANT_TYPE_CLIENT_CREDENTIALS,
                    required = true,
                  }
                },
                {
                  client_id = {
                    description = "The client ID for the application registration in the IdP.",
                    type          = "string",
                    encrypted     = true,
                    referenceable = true,
                    required      = false
                  },
                },
                {
                  client_secret = {
                    description = "The client secret for the application registration in the IdP.",
                    type          = "string",
                    encrypted     = true,
                    referenceable = true,
                    required      = false
                  },
                },
                {
                  username = {
                    description = "The username to use if `config.oauth.grant_type` is set to `password`.",
                    type          = "string",
                    encrypted     = true,
                    referenceable = true,
                    required      = false
                  },
                },
                {
                  password = {
                    description = "The password to use if `config.oauth.grant_type` is set to `password`.",
                    type          = "string",
                    encrypted     = true,
                    referenceable = true,
                    required      = false
                  },
                },
                {
                  scopes = {
                    description = "List of scopes to request from the IdP when obtaining a new token.",
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
                    description = "List of audiences passed to the IdP when obtaining a new token.",
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
                    description = "The method Kong should use to cache tokens issued by the IdP.",
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
                          description = "The shared dictionary used by the plugin to cache tokens if `config.cache.strategy` is set to `memory`.",
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
                    description = "The number of seconds to eagerly expire a cached token. By default, a cached token expires 5 seconds before its lifetime as defined in `expires_in`.",
                    type     = "integer",
                    default  = 5,
                    gt       = -1,
                    required = true
                  }
                },
                {
                  default_ttl = {
                    description = "The lifetime of a token without an explicit `expires_in` value.",
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
                    description = "The name of the header used to send the access token (obtained from the IdP) to the upstream service.",
                    type = "string",
                    default = "Authorization",
                    required = true,
                    len_min = 0
                  }
                },
                {
                  idp_error_response_status_code = {
                    description = "The response code to return to the consumer if Kong fails to obtain a token from the IdP.",
                    type = "integer",
                    default = 502,
                    required = true,
                    between = { 500, 599 }
                  }
                },
                {
                  idp_error_response_content_type = {
                    description = "The Content-Type of the response to return to the consumer if Kong fails to obtain a token from the IdP.",
                    type = "string",
                    default = "application/json; charset=utf-8",
                    required = true,
                    len_min = 0
                  }
                },
                {
                  idp_error_response_message = {
                    description = "The message to embed in the body of the response to return to the consumer if Kong fails to obtain a token from the IdP.",
                    type = "string",
                    default = "Failed to authenticate request to upstream",
                    required = true,
                    len_min = 0
                  }
                },
                {
                  idp_error_response_body_template = {
                    description = "The template to use to create the body of the response to return to the consumer if Kong fails to obtain a token from the IdP.",
                    type = "string",
                    default = "{ \"code\": \"{{status}}\", \"message\": \"{{message}}\" }",
                    required = true,
                    len_min = 0
                  }
                },
                {
                  purge_token_on_upstream_status_codes = {
                    description = "An array of status codes which will force an access token to be purged when returned by the upstream. An empty array will disable this functionality.",
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
