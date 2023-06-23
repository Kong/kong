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
        {
          session_redis_prefix = { description = "The Redis session key prefix.", required = false,
            type     = "string",
          },
        },
        {
          session_redis_socket = { description = "The Redis unix socket path.", required = false,
            type     = "string",
          },
        },
        {
          session_redis_host = { description = "The Redis host IP.", required = false,
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
          session_redis_username = { description = "Redis username if the `redis` session storage is defined and ACL authentication is desired.If undefined, ACL authentication will not be performed.  This requires Redis v6.0.0+. The username **cannot** be set to `default`.", required = false,
            type = "string",
            referenceable = true,
          },
        },
        {
          session_redis_password = { description = "Password to use for Redis connection when the `redis` session storage is defined. If undefined, no auth commands are sent to Redis. This value is pulled from", required = false,
            type = "string",
            encrypted = true,
            referenceable = true,
          },
        },
        {
          session_redis_connect_timeout = { description = "The Redis connection timeout in milliseconds.", required = false,
            type = "integer",
          },
        },
        {
          session_redis_read_timeout = { description = "The Redis read timeout in milliseconds.", required = false,
            type = "integer",
          },
        },
        {
          session_redis_send_timeout = { description = "The Redis send timeout in milliseconds.", required = false,
            type = "integer",
          },
        },
        {
          session_redis_ssl = { description = "Use SSL/TLS for the Redis connection.", required = false,
            type     = "boolean",
            default  = false,
          },
        },
        {
          session_redis_ssl_verify = { description = "Verify the Redis server certificate.", required = false,
            type     = "boolean",
            default  = false,
          },
        },
        {
          session_redis_server_name = { description = "The SNI used for connecting to the Redis server.", required = false,
            type     = "string",
          },
        },
        {
          session_redis_cluster_nodes = { description = "The Redis cluster node host. Takes an array of host records, with either `ip` or `host`, and `port` values.", required = false,
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
          session_redis_cluster_max_redirections = { description = "The Redis cluster maximum redirects.", required = false,
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
              ngx.log(ngx.INFO, "[saml] session_cookie_renew option does not exist anymore")
            end,
          },
        },
        {
          session_cookie_maxsize = {
            type = "integer",
            func = function()
              -- new library has this hard coded
              ngx.log(ngx.INFO, "[saml] session_cookie_maxsize option does not exist anymore")
            end,
          },
        },
        {
          session_strategy = {
            type = "string",
            func = function()
              -- new library supports only the so called regenerate strategy
              ngx.log(ngx.INFO, "[saml] session_strategy option does not exist anymore")
            end,
          },
        },
        {
          session_compressor = {
            type = "string",
            func = function()
              -- new library decides this based on data size
              ngx.log(ngx.INFO, "[saml] session_compressor option does not exist anymore")
            end,
          },
        },
        {
          session_auth_ttl = {
            type = "number",
            func = function()
              ngx.log(ngx.INFO, "[saml] session_auth_ttl option does not exist anymore")
            end,
          },
        },
      },
    }},
  },
}