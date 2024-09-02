-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local Schema = require "kong.db.schema"
local redis = require "kong.enterprise_edition.tools.redis.v2"
local typedefs = require "kong.db.schema.typedefs"
local tablex = require "pl.tablex"

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

local REDIS_SAML_SCHEMA = tablex.deepcopy(redis.config_schema)
table.insert(REDIS_SAML_SCHEMA.fields,
  { prefix = {
      description = "The Redis session key prefix.",
      required = false,
      type     = "string",
  } }
)
table.insert(REDIS_SAML_SCHEMA.fields,
  { socket = { description = "The Redis unix socket path.",
        required = false,
        type     = "string",
  } }
)


return {
  name = "saml",
  fields = {
    { consumer = typedefs.no_consumer },
    { protocols = typedefs.protocols_http },
    { consumer_group = typedefs.no_consumer_group },
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
          idp_certificate = { description = "The public certificate provided by the IdP. This is used to validate responses from the IdP.  Only include the contents of the certificate. Do not include the header (`BEGIN CERTIFICATE`) and footer (`END CERTIFICATE`) lines.", type = "string",
            required = false,
            encrypted = true,
            referenceable = true,
          },
        },
        {
          response_encryption_key = { description = "The private encryption key required to decrypt encrypted assertions.", type = "string",
            required = false,
            encrypted = true,
            referenceable = true,
          },
        },
        {
          request_signing_key = { description = "The private key for signing requests.  If this parameter is set, requests sent to the IdP are signed.  The `request_signing_certificate` parameter must be set as well.", type = "string",
            required = false,
            encrypted = true,
            referenceable = true,
          },
        },
        {
          request_signing_certificate = { description = "The certificate for signing requests.", type = "string",
            required = false,
            encrypted = true,
            referenceable = true,
          },
        },
        {
          request_signature_algorithm = { description = "The signature algorithm for signing Authn requests. Options available are: - `SHA256` - `SHA384` - `SHA512`", type = "string",
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
          request_digest_algorithm = { description = "The digest algorithm for Authn requests: - `SHA256` - `SHA1`", type = "string",
            one_of = {
              "SHA256",
              "SHA1"
            },
            default = "SHA256",
            required = false,
          },
        },
        {
          response_signature_algorithm = { description = "The algorithm for validating signatures in SAML responses. Options available are: - `SHA256` - `SHA384` - `SHA512`", type = "string",
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
          response_digest_algorithm = { description = "The algorithm for verifying digest in SAML responses: - `SHA256` - `SHA1`", type = "string",
            one_of = {
              "SHA256",
              "SHA1"
            },
            default = "SHA256",
            required = false,
          },
        },
        {
          issuer = { description = "The unique identifier of the IdP application. Formatted as a URL containing information about the IdP so the SP can validate that the SAML assertions it receives are issued from the correct IdP.", type = "string",
            required = true,
          },
        },
        {
          nameid_format = { description = "The requested `NameId` format. Options available are: - `Unspecified` - `EmailAddress` - `Persistent` - `Transient`", type = "string",
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
          validate_assertion_signature = { description = "Enable signature validation for SAML responses.", type = "boolean",
            required = false,
            default = true,
          },
        },
        {
          anonymous = { description = "An optional string (consumer UUID or username) value to use as an “anonymous” consumer. If not set, a Kong Consumer must exist for the SAML IdP user credentials, mapping the username format to the Kong Consumer username.", required = false,
            type     = "string",
          },
        },

        -- session related configuration
        {
          session_secret = { description = "The session secret. This must be a random string of 32 characters from the base64 alphabet (letters, numbers, `/`, `_` and `+`). It is used as the secret key for encrypting session data as well as state information that is sent to the IdP in the authentication exchange.", required      = true,
            type          = "string",
            encrypted     = true,
            referenceable = true,
            match         = "^[0-9a-zA-Z/_+]+$",
            len_min       = 32,
            len_max       = 32,
          },
        },
        {
          session_audience = { description = "The session audience, for example \"my-application\"", required = false,
            type     = "string",
            default  = "default",
          },
        },
        {
          session_cookie_name = { description = "The session cookie name.", required = false,
            type     = "string",
            default  = "session",
          },
        },
        {
          session_remember = { description = "Enables or disables persistent sessions", required = false,
            type     = "boolean",
            default  = false,
          },
        },
        {
          session_remember_cookie_name = { description = "Persistent session cookie name", required = false,
            type     = "string",
            default  = "remember",
          },
        },
        {
          session_remember_rolling_timeout = { description = "Persistent session rolling timeout in seconds.", required = false,
            type     = "number",
            default  = 604800,
          },
        },
        {
          session_remember_absolute_timeout = { description = "Persistent session absolute timeout in seconds.", required = false,
            type     = "number",
            default  = 2592000,
          },
        },
        {
          session_idling_timeout = { description = "The session cookie idle time in seconds.", required = false,
            type     = "number",
            default  = 900,
          },
        },
        {
          session_rolling_timeout = { description = "The session cookie absolute timeout in seconds. Specifies how long the session can be used until it is no longer valid.", required = false,
            type     = "number",
            default  = 3600,
          },
        },
        {
          session_absolute_timeout = { description = "The session cookie absolute timeout in seconds. Specifies how long the session can be used until it is no longer valid.",
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
          session_cookie_domain = { description = "The session cookie domain flag.", required = false,
            type     = "string",
          },
        },
        {
          session_cookie_same_site = { description = "Controls whether a cookie is sent with cross-origin requests, providing some protection against cross-site request forgery attacks.", required = false,
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
          session_cookie_http_only = { description = "Forbids JavaScript from accessing the cookie, for example, through the `Document.cookie` property.", required = false,
            type     = "boolean",
            default  = true,
          },
        },
        {
          session_cookie_secure = { description = "The cookie is only sent to the server when a request is made with the https:scheme (except on localhost), and therefore is more resistant to man-in-the-middle attacks.", required = false,
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
          session_storage = { description = "The session storage for session data: - `cookie`: stores session data with the session cookie. The session cannot be invalidated or revoked without changing the session secret, but is stateless, and doesn't require a database. - `memcached`: stores session data in memcached - `redis`: stores session data in Redis", required = false,
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
          session_store_metadata = { description = "Configures whether or not session metadata should be stored. This includes information about the active sessions for the `specific_audience` belonging to a specific subject.", required = false,
            type     = "boolean",
            default  = false,
          },
        },
        {
          session_enforce_same_subject = { description = "When set to `true`, audiences are forced to share the same subject.", required = false,
            type     = "boolean",
            default  = false,
          },
        },
        {
          session_hash_subject = { description = "When set to `true`, the value of subject is hashed before being stored. Only applies when `session_store_metadata` is enabled.", required = false,
            type     = "boolean",
            default  = false,
          },
        },
        {
          session_hash_storage_key = { description = "When set to `true`, the storage key (session ID) is hashed for extra security. Hashing the storage key means it is impossible to decrypt data from the storage without a cookie.", required = false,
            type     = "boolean",
            default  = false,
          },
        },
        {
          session_memcached_prefix = { description = "The memcached session key prefix.", required = false,
            type     = "string",
          },
        },
        {
          session_memcached_socket = { description = "The memcached unix socket path.", required = false,
            type     = "string",
          },
        },
        {
          session_memcached_host = { description = "The memcached host.", required = false,
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
        { redis = REDIS_SAML_SCHEMA },
      },
      shorthand_fields = {
        -- TODO: deprecated forms, to be removed in Kong 4.0
        {
          session_cookie_lifetime = {
            type = "number",
            deprecation = {
              message = "openid-connect: config.session_cookie_lifetime is deprecated, please use config.session_rolling_timeout instead",
              removal_in_version = "4.0", },
            func = function(value)
              return { session_rolling_timeout = value }
            end,
          },
        },
        {
          session_cookie_idletime = {
            type = "number",
            deprecation = {
              message = "openid-connect: config.session_cookie_idletime is deprecated, please use config.session_idling_timeout instead",
              removal_in_version = "4.0", },
            func = function(value)
              return { session_idling_timeout = value }
            end,
          },
        },
        {
          session_cookie_samesite = {
            type = "string",
            deprecation = {
              message = "openid-connect: config.session_cookie_samesite is deprecated, please use config.session_cookie_same_site instead",
              removal_in_version = "4.0", },
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
            deprecation = {
              message = "openid-connect: config.session_cookie_httponly is deprecated, please use config.session_cookie_http_only instead",
              removal_in_version = "4.0", },
            func = function(value)
              return { session_cookie_http_only = value }
            end,
          },
        },
        {
          session_memcache_prefix = {
            type = "string",
            deprecation = {
              message = "openid-connect: config.session_memcache_prefix is deprecated, please use config.session_memcached_prefix instead",
              removal_in_version = "4.0", },
            func = function(value)
              return { session_memcached_prefix = value }
            end,
          },
        },
        {
          session_memcache_socket = {
            type = "string",
            deprecation = {
              message = "openid-connect: config.session_memcache_socket is deprecated, please use config.session_memcached_socket instead",
              removal_in_version = "4.0", },
            func = function(value)
              return { session_memcached_socket = value }
            end,
          },
        },
        {
          session_memcache_host = {
            type = "string",
            deprecation = {
              message = "openid-connect: config.session_memcache_host is deprecated, please use config.session_memcached_host instead",
              removal_in_version = "4.0", },
            func = function(value)
              return { session_memcached_host = value }
            end,
          },
        },
        {
          session_memcache_port = {
            type = "integer",
            deprecation = {
              message = "openid-connect: config.session_memcache_port is deprecated, please use config.session_memcached_port instead",
              removal_in_version = "4.0", },
            func = function(value)
              return { session_memcached_port = value }
            end,
          },
        },
        {
          session_cookie_renew = {
            type = "number",
            deprecation = {
              message = "openid-connect: config.session_cookie_renew option does not exist anymore",
              removal_in_version = "4.0", },
            func = function() end,
          },
        },
        {
          session_cookie_maxsize = {
            type = "integer",
            deprecation = {
              message = "openid-connect: config.session_cookie_maxsize option does not exist anymore",
              removal_in_version = "4.0", },
            func = function() end,
          },
        },
        {
          session_strategy = {
            type = "string",
            deprecation = {
              message = "openid-connect: config.session_strategy option does not exist anymore",
              removal_in_version = "4.0", },
            func = function() end,
          },
        },
        {
          session_compressor = {
            type = "string",
            deprecation = {
              message = "openid-connect: config.session_compressor option does not exist anymore",
              removal_in_version = "4.0", },
            func = function() end,
          },
        },
        {
          session_auth_ttl = {
            type = "number",
            deprecation = {
              message = "openid-connect: config.session_auth_ttl option does not exist anymore",
              removal_in_version = "4.0", },
            func = function() end,
          },
        },

        -- Redis renaming: deprecated forms, to be removed in Kong 4.0
        { session_redis_prefix = {
          type = "string",
          deprecation = {
            replaced_with = { { path = {'redis', 'prefix'} } },
            message = "saml: config.session_redis_prefix is deprecated, please use config.redis.prefix instead",
            removal_in_version = "4.0", },
          func = function(value)
            return { redis = { prefix = value } }
          end
        } },
        { session_redis_socket = {
          type = "string",
          deprecation = {
            replaced_with = { { path = {'redis', 'socket'} } },
            message = "saml: config.session_redis_socket is deprecated, please use config.redis.socket instead",
            removal_in_version = "4.0", },
          func = function(value)
            return { redis = { socket = value } }
          end
        }},
        { session_redis_host = {
          type = "string",
          deprecation = {
            replaced_with = { { path = {'redis', 'host'} } },
            message = "saml: config.session_redis_host is deprecated, please use config.redis.host instead",
            removal_in_version = "4.0", },
          func = function(value)
            return { redis = { host = value } }
          end
        } },
        { session_redis_port = {
          type = "integer",
          deprecation = {
            replaced_with = { { path = {'redis', 'port'} } },
            message = "saml: config.session_redis_port is deprecated, please use config.redis.port instead",
            removal_in_version = "4.0", },
          func = function(value)
            return { redis = { port = value } }
          end
        } },
        {
          session_redis_username = {
            type = "string",
            deprecation = {
              replaced_with = { { path = {'redis', 'username'} } },
              message = "saml: config.redis_host is deprecated, please use config.redis.host instead",
              removal_in_version = "4.0", },
            func = function(value)
              return { redis = { username = value } }
            end
          },
        },
        {
          session_redis_password = {
            type = "string",
            deprecation = {
              replaced_with = { { path = {'redis', 'password'} } },
              message = "saml: config.session_redis_password is deprecated, please use config.redis.password instead",
              removal_in_version = "4.0", },
            func = function(value)
              return { redis = { password = value } }
            end
          },
        },
        {
          session_redis_connect_timeout = {
            type = "integer",
            deprecation = {
              replaced_with = { { path = {'redis', 'connect_timeout'} } },
              message = "saml: config.session_redis_connect_timeout is deprecated, please use config.redis.connect_timeout instead",
              removal_in_version = "4.0", },
            func = function(value)
              return { redis = { connect_timeout = value } }
            end
          },
        },
        {
          session_redis_read_timeout = {
            type = "integer",
            deprecation = {
              replaced_with = { { path = {'redis', 'read_timeout'} } },
              message = "saml: config.session_redis_read_timeout is deprecated, please use config.redis.read_timeout instead",
              removal_in_version = "4.0", },
            func = function(value)
              return { redis = { read_timeout = value } }
            end
          },
        },
        {
          session_redis_send_timeout = {
            type = "integer",
            deprecation = {
              replaced_with = { { path = {'redis', 'send_timeout'} } },
              message = "saml: config.session_redis_send_timeout is deprecated, please use config.redis.send_timeout instead",
              removal_in_version = "4.0", },
            func = function(value)
              return { redis = { send_timeout = value } }
            end
          },
        },
        {
          session_redis_ssl = {
            type = "boolean",
            deprecation = {
              replaced_with = { { path = {'redis', 'ssl'} } },
              message = "saml: config.session_redis_ssl is deprecated, please use config.redis.ssl instead",
              removal_in_version = "4.0", },
            func = function(value)
              return { redis = { ssl = value } }
            end
          },
        },
        {
          session_redis_ssl_verify = {
            type = "boolean",
            deprecation = {
              replaced_with = { { path = {'redis', 'ssl_verify'} } },
              message = "saml: config.session_redis_ssl_verify is deprecated, please use config.redis.ssl_verify instead",
              removal_in_version = "4.0", },
            func = function(value)
              return { redis = { ssl_verify = value } }
            end
          },
        },
        {
          session_redis_server_name = {
            type = "string",
            deprecation = {
              replaced_with = { { path = {'redis', 'server_name'} } },
              message = "saml: config.session_redis_server_name is deprecated, please use config.redis.server_name instead",
              removal_in_version = "4.0", },
            func = function(value)
              return { redis = { server_name = value } }
            end
          },
        },
        {
          session_redis_cluster_nodes = {
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
              }
            },
            deprecation = {
              replaced_with = { { path = {'redis', 'cluster_nodes'} } },
              message = "saml: config.session_redis_cluster_nodes is deprecated, please use config.redis.cluster_nodes instead",
              removal_in_version = "4.0", },
            func = function(value)
              return { redis = { cluster_nodes = value } }
            end
          },
        },
        {
          session_redis_cluster_max_redirections = {
            type = "integer",
            deprecation = {
              replaced_with = { { path = {'redis', 'cluster_max_redirections'} } },
              message = "saml: config.session_redis_cluster_max_redirections is deprecated, please use config.redis.cluster_max_redirections instead",
              removal_in_version = "4.0", },
            func = function(value)
              return { redis = { cluster_max_redirections = value } }
            end
          },
        },
        {
          session_redis_cluster_maxredirections = {
            type = "integer",
            deprecation = {
              replaced_with = { { path = {'redis', 'cluster_max_redirections'} } },
              message = "saml: config.session_redis_cluster_maxredirections is deprecated, please use config.redis.cluster_max_redirections instead",
              removal_in_version = "4.0", },
            func = function(value)
              return { redis = { cluster_max_redirections = value } }
            end,
          },
        },
      },
    }},
  },
  entity_checks = {
    { custom_entity_check = {
      field_sources = { "config" },
      fn = function(entity)
        local config = entity.config
        if config.session_storage == "redis" then
          if config.redis == ngx.null or (
              config.redis.host == ngx.null and
              config.redis.socket == ngx.null and
              config.redis.sentinel_nodes == ngx.null and
              config.redis.cluster_nodes == ngx.null) then
            return nil, "No redis config provided"
          end
        end

        return true
      end } }
  },
}
