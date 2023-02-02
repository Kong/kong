-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local Schema = require "kong.db.schema"


local typedefs = require "kong.db.schema.typedefs"


local function validate_parameters(config)
  -- explicit ngx.null comparisons needed below because of https://konghq.atlassian.net/browse/FT-3631
  if config.request_signing_key ~= ngx.null and config.request_signing_certificate == ngx.null then
    return false, "'request_signing_certificate' is required when 'request_signing_key' is set"
  end

  if config.request_signing_certificate ~= ngx.null and config.request_signing_key == ngx.null then
    return false, "'request_signing_key' is required when 'request_signing_certificate' is set"
  end

  if config.validate_assertion_signature and config.idp_certificate == ngx.null then
    return false, "'idp_certificate' is required if 'validate_assertion_signature' is set to true"
  end

  return true
end


local session_headers = Schema.define({
  type = "set",
  elements = {
    type = "string",
    one_of = {
      "id",
      "audience",
      "subject",
      "timeout",
      "idling-timeout",
      "rolling-timeout",
      "absolute-timeout",
    },
  },
})


return {
  name = "saml",
  fields = {
    { consumer = typedefs.no_consumer },
    { protocols = typedefs.protocols_http },
    { config = {
      type = "record",
      custom_validator = validate_parameters,
      fields = {
        {
          assertion_consumer_path = typedefs.path {
            required = true,
          },
        },
        {
          idp_sso_url = typedefs.url {
            required = true,
          },
        },
        {
          idp_certificate = {
            type = "string",
            required = false,
            encrypted = true,
            referenceable = true,
          },
        },
        {
          response_encryption_key = {
            type = "string",
            required = false,
            encrypted = true,
            referenceable = true,
          },
        },
        {
          request_signing_key = {
            type = "string",
            required = false,
            encrypted = true,
            referenceable = true,
          },
        },
        {
          request_signing_certificate = {
            type = "string",
            required = false,
            encrypted = true,
            referenceable = true,
          },
        },
        {
          request_signature_algorithm = {
            type = "string",
            one_of = {
              "SHA256",
              "SHA384",
              "SHA512"
            },
            default = "SHA256",
            required = false,
          },
        },
        {
          request_digest_algorithm = {
            type = "string",
            one_of = {
              "SHA256",
              "SHA1"
            },
            default = "SHA256",
            required = false,
          },
        },
        {
          response_signature_algorithm = {
            type = "string",
            one_of = {
              "SHA256",
              "SHA384",
              "SHA512"
            },
            default = "SHA256",
            required = false,
          },
        },
        {
          response_digest_algorithm = {
            type = "string",
            one_of = {
              "SHA256",
              "SHA1"
            },
            default = "SHA256",
            required = false,
          },
        },
        {
          issuer = {
            type = "string",
            required = true,
          },
        },
        {
          nameid_format = {
          type = "string",
          one_of = {
            "Unspecified",
            "EmailAddress",
            "Persistent",
            "Transient"
          },
          default = "EmailAddress",
          required = false,
          },
        },
        {
          validate_assertion_signature = {
            type = "boolean",
            required = false,
            default = true,
          },
        },
        {
          anonymous = {
            required = false,
            type     = "string",
          },
        },

        -- session related configuration
        {
          session_secret = {
            required      = true,
            type          = "string",
            encrypted     = true,
            referenceable = true,
            match         = "^[0-9a-zA-Z/_+]+$",
            len_min       = 32,
            len_max       = 32,
          },
        },
        {
          session_audience = {
            required = false,
            type     = "string",
            default  = "default",
          },
        },
        {
          session_cookie_name = {
            required = false,
            type     = "string",
            default  = "session",
          },
        },
        {
          session_remember = {
            required = false,
            type     = "boolean",
            default  = false,
          },
        },
        {
          session_remember_cookie_name = {
            required = false,
            type     = "string",
            default  = "remember",
          },
        },
        {
          session_remember_rolling_timeout = {
            required = false,
            type     = "number",
            default  = 604800,
          },
        },
        {
          session_remember_absolute_timeout = {
            required = false,
            type     = "number",
            default  = 2592000,
          },
        },
        {
          session_idling_timeout = {
            required = false,
            type     = "number",
            default  = 900,
          },
        },
        {
          session_rolling_timeout = {
            required = false,
            type     = "number",
            default  = 3600,
          },
        },
        {
          session_absolute_timeout = {
            required = false,
            type     = "number",
            default  = 86400,
          },
        },
        {
          session_cookie_path = typedefs.path {
            required = false,
            default  = "/",
          },
        },
        {
          session_cookie_domain = {
            required = false,
            type     = "string",
          },
        },
        {
          session_cookie_same_site = {
            required = false,
            type     = "string",
            default  = "Lax",
            one_of   = {
              "Strict",
              "Lax",
              "None",
              "Default",
            },
          },
        },
        {
          session_cookie_http_only = {
            required = false,
            type     = "boolean",
            default  = true,
          },
        },
        {
          session_cookie_secure = {
            required = false,
            type     = "boolean",
          },
        },
        {
          session_request_headers = session_headers,
        },
        {
          session_response_headers = session_headers,
        },
        {
          session_storage = {
            required = false,
            type     = "string",
            default  = "cookie",
            one_of   = {
              "cookie",
              "memcache", -- TODO: deprecated, to be removed in Kong 4.0
              "memcached",
              "redis",
            },
          },
        },
        {
          session_store_metadata = {
            required = false,
            type     = "boolean",
            default  = false,
          },
        },
        {
          session_enforce_same_subject = {
            required = false,
            type     = "boolean",
            default  = false,
          },
        },
        {
          session_hash_subject = {
            required = false,
            type     = "boolean",
            default  = false,
          },
        },
        {
          session_hash_storage_key = {
            required = false,
            type     = "boolean",
            default  = false,
          },
        },
        {
          session_memcached_prefix = {
            required = false,
            type     = "string",
          },
        },
        {
          session_memcached_socket = {
            required = false,
            type     = "string",
          },
        },
        {
          session_memcached_host = {
            required = false,
            type     = "string",
            default  = "127.0.0.1",
          },
        },
        {
          session_memcached_port = typedefs.port {
            required = false,
            default  = 11211,
          },
        },
        {
          session_redis_prefix = {
            required = false,
            type     = "string",
          },
        },
        {
          session_redis_socket = {
            required = false,
            type     = "string",
          },
        },
        {
          session_redis_host = {
            required = false,
            type     = "string",
            default  = "127.0.0.1",
          },
        },
        {
          session_redis_port = typedefs.port {
            required = false,
            default  = 6379,
          },
        },
        {
          session_redis_username = {
            required = false,
            type = "string",
            referenceable = true,
          },
        },
        {
          session_redis_password = {
            required = false,
            type = "string",
            encrypted = true,
            referenceable = true,
          },
        },
        {
          session_redis_connect_timeout = {
            required = false,
            type = "integer",
          },
        },
        {
          session_redis_read_timeout = {
            required = false,
            type = "integer",
          },
        },
        {
          session_redis_send_timeout = {
            required = false,
            type = "integer",
          },
        },
        {
          session_redis_ssl = {
            required = false,
            type     = "boolean",
            default  = false,
          },
        },
        {
          session_redis_ssl_verify = {
            required = false,
            type     = "boolean",
            default  = false,
          },
        },
        {
          session_redis_server_name = {
            required = false,
            type     = "string",
          },
        },
        {
          session_redis_cluster_nodes = {
            required = false,
            type = "array",
            elements = {
              type = "record",
              fields = {
                {
                  ip = typedefs.host {
                    required = true,
                    default  = "127.0.0.1",
                  },
                },
                {
                  port = typedefs.port {
                    default = 6379,
                  },
                },
              },
            },
          },
        },
        {
          session_redis_cluster_max_redirections = {
            required = false,
            type = "integer",
          },
        },
      },
      shorthand_fields = {
        -- TODO: deprecated forms, to be removed in Kong 4.0
        {
          session_cookie_lifetime = {
            type = "number",
            func = function(value)
              return { session_rolling_timeout = value }
            end,
          },
        },
        {
          session_cookie_idletime = {
            type = "number",
            func = function(value)
              return { session_idling_timeout = value }
            end,
          },
        },
        {
          session_cookie_samesite = {
            type = "string",
            func = function(value)
              if value == "off" then
                value = "Lax"
              end
              return { session_cookie_same_site = value }
            end,
          },
        },
        {
          session_cookie_httponly = {
            type = "boolean",
            func = function(value)
              return { session_cookie_http_only = value }
            end,
          },
        },
        {
          session_memcache_prefix = {
            type = "string",
            func = function(value)
              return { session_memcached_prefix = value }
            end,
          },
        },
        {
          session_memcache_socket = {
            type = "string",
            func = function(value)
              return { session_memcached_socket = value }
            end,
          },
        },
        {
          session_memcache_host = {
            type = "string",
            func = function(value)
              return { session_memcached_host = value }
            end,
          },
        },
        {
          session_memcache_port = {
            type = "integer",
            func = function(value)
              return { session_memcached_port = value }
            end,
          },
        },
        {
          session_redis_cluster_maxredirections = {
            type = "integer",
            func = function(value)
              return { session_redis_cluster_max_redirections = value }
            end,
          },
        },
        {
          session_cookie_renew = {
            type = "number",
            func = function()
              -- new library calculates this
              ngx.log(ngx.INFO, "[saml] session_cookie_renew option does not exists anymore")
            end,
          },
        },
        {
          session_cookie_maxsize = {
            type = "integer",
            func = function()
              -- new library has this hard coded
              ngx.log(ngx.INFO, "[saml] session_cookie_maxsize option does not exists anymore")
            end,
          },
        },
        {
          session_strategy = {
            type = "string",
            func = function()
              -- new library supports only the so called regenerate strategy
              ngx.log(ngx.INFO, "[saml] session_strategy option does not exists anymore")
            end,
          },
        },
        {
          session_compressor = {
            type = "string",
            func = function()
              -- new library decides this based on data size
              ngx.log(ngx.INFO, "[saml] session_compressor option does not exists anymore")
            end,
          },
        },
      },
    }},
  },
}
