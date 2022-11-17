-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"

local crypt    = require "kong.plugins.saml.utils.crypt"


local function validate_parameters(conf)

  if conf["request_signing_key"] and not conf["request_signing_certificate"] then
    return false, "'request_signing_certificate' is required when 'request_signing_key' is set"
  end

  if conf["request_signing_certificate"] and not conf["request_signing_key"] then
    return false, "'request_signing_key' is required when 'request_signing_certificate' is set"
  end

  if conf["validate_assertion_signature"] and not conf["idp_certificate"] then
    return false, "'idp_certificate' is required if 'validate_assertion_signature' is set to true"
  end

  if not ngx.re.match(conf["session_secret"], "^[0-9a-zA-Z/_+]{32}$") then
    return false, "'session_secret' must be a string of 32 characters from the base64 alphabet"
  end

  return true
end


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
            required = false,
            type     = "string",
            encrypted = true,
            default = crypt.generate_key(),
            referenceable = true,
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
          session_cookie_lifetime = {
            required = false,
            type     = "number",
            default  = 3600,
          },
        },
        {
          session_cookie_idletime = {
            required = false,
            type     = "number",
          },
        },
        {
          session_cookie_renew = {
            required = false,
            type     = "number",
            default  = 600,
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
          session_cookie_samesite = {
            required = false,
            type     = "string",
            default  = "Lax",
            one_of   = {
              "Strict",
              "Lax",
              "None",
              "off"
            },
          },
        },
        {
          session_cookie_httponly = {
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
        { session_auth_ttl = {
            type = "number",
            required = true,
            default = 5400,  -- 90 mins,
        }, },
        {
          session_cookie_maxsize = {
            required = false,
            type     = "integer",
            default  = 4000,
          },
        },
        {
          session_strategy = {
            required = false,
            type     = "string",
            default  = "default",
            one_of   = {
              "default",
              "regenerate",
            },
          },
        },
        {
          session_compressor = {
            required = false,
            type     = "string",
            default  = "none",
            one_of   = {
              "none",
              "zlib",
            },
          },
        },
        {
          session_storage = {
            required = false,
            type     = "string",
            default  = "cookie",
            one_of   = {
              "cookie",
              "memcache",
              "redis",
            },
          },
        },
        {
          session_memcache_prefix = {
            required = false,
            type     = "string",
            default  = "sessions",
          },
        },
        {
          session_memcache_socket = {
            required = false,
            type     = "string",
          },
        },
        {
          session_memcache_host = {
            required = false,
            type     = "string",
            default  = "127.0.0.1",
          },
        },
        {
          session_memcache_port = typedefs.port {
            required = false,
            default  = 11211,
          },
        },
        {
          session_redis_prefix = {
            required = false,
            type     = "string",
            default  = "sessions",
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
            type     = "string",
            referenceable = true,
          },
        },
        {
          session_redis_password = {
            required = false,
            type     = "string",
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
          session_redis_cluster_maxredirections = {
            required = false,
            type = "integer",
          },
        },
      },
      entity_checks = {
        { conditional = {

        }},
      },
    }},
  },
}
