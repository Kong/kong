-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local Schema = require "kong.db.schema"


local typedefs  = require "kong.db.schema.typedefs"
local oidcdefs  = require "kong.plugins.openid-connect.typedefs"
local cache     = require "kong.plugins.openid-connect.cache"
local arguments = require "kong.plugins.openid-connect.arguments"


local get_phase = ngx.get_phase


local function validate_issuer(conf)
  local phase = get_phase()
  if phase ~= "access" and phase ~= "content" then
    return true
  end

  local args = arguments(conf)

  local issuer_uri = args.get_conf_arg("issuer")
  if not issuer_uri then
    return true
  end

  local options = args.get_http_opts({
    extra_jwks_uris = args.get_conf_arg("extra_jwks_uris"),
    headers         = args.get_conf_args("discovery_headers_names", "discovery_headers_values"),
  })

  local keys = cache.issuers.rediscover(issuer_uri, options)
  if not keys then
    return false, "openid connect discovery failed"
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


local config = {
  name = "openid-connect",
  fields = {
    { consumer  = typedefs.no_consumer    },
    { protocols = typedefs.protocols_http },
    { config    = {
        type             = "record",
        custom_validator = validate_issuer,
        fields           = {
          {
            issuer = typedefs.url {
              required = true,
            },
          },
          {
            discovery_headers_names = {
              required = false,
              type     = "array",
              elements = {
                type   = "string",
              },
            },
          },
          {
            discovery_headers_values = {
              required = false,
              type     = "array",
              elements = {
                type   = "string",
              },
            },
          },
          {
            extra_jwks_uris = {
              required = false,
              type     = "set",
              elements = typedefs.url,
            },
          },
          {
            rediscovery_lifetime = {
              required = false,
              type     = "number",
              default  = 30,
            },
          },
          {
            auth_methods = {
              required = false,
              type     = "array",
              default  = {
                "password",
                "client_credentials",
                "authorization_code",
                "bearer",
                "introspection",
                "userinfo",
                "kong_oauth2",
                "refresh_token",
                "session",
              },
              elements = {
                type   = "string",
                one_of = {
                  "password",
                  "client_credentials",
                  "authorization_code",
                  "bearer",
                  "introspection",
                  "userinfo",
                  "kong_oauth2",
                  "refresh_token",
                  "session",
                },
              },
            },
          },
          {
            client_id = {
              required  = false,
              type      = "array",
              encrypted = true,
              elements  = {
                type    = "string",
                referenceable = true,
              },
            },
          },
          {
            client_secret = {
              required  = false,
              type      = "array",
              encrypted = true,
              elements  = {
                type    = "string",
                referenceable = true,
              },
            },
          },
          {
            client_auth = {
              required  = false,
              type      = "array",
              elements  = {
                type    = "string",
                one_of  = {
                  "client_secret_basic",
                  "client_secret_post",
                  "client_secret_jwt",
                  "private_key_jwt",
                  "none",
                },
              },
            },
          },
          {
            client_jwk  = {
              required  = false,
              type      = "array",
              elements  = oidcdefs.jwk,
            },
          },
          {
            client_alg  = {
              required  = false,
              type      = "array",
              elements  = {
                type    = "string",
                one_of = {
                  "HS256",
                  "HS384",
                  "HS512",
                  "RS256",
                  "RS384",
                  "RS512",
                  "ES256",
                  "ES384",
                  "ES512",
                  "PS256",
                  "PS384",
                  "PS512",
                  "EdDSA",
                },
              },
            },
          },
          {
            client_arg = {
              required = false,
              type     = "string",
              default  = "client_id",
            },
          },
          {
            redirect_uri = {
              required = false,
              type     = "array",
              elements = typedefs.url,
            },
          },
          {
            login_redirect_uri = {
              required = false,
              type     = "array",
              elements = typedefs.url,
            },
          },
          {
            logout_redirect_uri = {
              required = false,
              type     = "array",
              elements = typedefs.url,
            },
          },
          {
            forbidden_redirect_uri = {
              required = false,
              type     = "array",
              elements = typedefs.url,
            },
          },
          {
            forbidden_error_message = {
              required = false,
              type     = "string",
              default  = "Forbidden",
            },
          },
          {
            forbidden_destroy_session = {
              required = false,
              type     = "boolean",
              default  = true,
            },
          },
          {
            unauthorized_redirect_uri = {
              required = false,
              type     = "array",
              elements = typedefs.url,
            },
          },
          {
            unauthorized_error_message = {
              required = false,
              type     = "string",
              default  = "Unauthorized",
            },
          },
          {
            unexpected_redirect_uri = {
              required = false,
              type     = "array",
              elements = typedefs.url,
            },
          },
          {
            response_mode = {
              required = false,
              type     = "string",
              default  = "query",
              one_of   = {
                "query",
                "form_post",
                "fragment",
              },
            },
          },
          {
            response_type = {
              required = false,
              type     = "array",
              default  = {
                "code",
              },
              elements = {
                type = "string",
              },
            },
          },
          {
            scopes = {
              required = false,
              type     = "array",
              default  = {
                "openid",
              },
              elements = {
                type = "string",
              },
            },
          },
          {
            audience = {
              required = false,
              type     = "array",
              elements = {
                type = "string",
              },
            },
          },
          {
            issuers_allowed = {
              required = false,
              type     = "array",
              elements = {
                type = "string",
              },
            },
          },
          {
            scopes_required = {
              required = false,
              type     = "array",
              elements = {
                type = "string",
              },
            },
          },
          {
            scopes_claim = {
              required = false,
              type     = "array",
              default  = { "scope" },
              elements = {
                type = "string",
              },
            },
          },
          {
            audience_required = {
              required = false,
              type     = "array",
              elements = {
                type = "string",
              },
            },
          },
          {
            audience_claim = {
              required = false,
              type     = "array",
              default  = { "aud" },
              elements = {
                type = "string",
              },
            },
          },
          {
            groups_required = {
              required = false,
              type     = "array",
              elements = {
                type = "string",
              },
            },
          },
          {
            groups_claim = {
              required = false,
              type     = "array",
              default  = { "groups" },
              elements = {
                type = "string",
              },
            },
          },
          {
            roles_required = {
              required = false,
              type     = "array",
              elements = {
                type = "string",
              },
            },
          },
          {
            roles_claim = {
              required = false,
              type     = "array",
              default  = { "roles" },
              elements = {
                type = "string",
              },
            },
          },
          {
            domains = {
              required = false,
              type     = "array",
              elements = {
                type = "string",
              },
            },
          },
          {
            max_age = {
              required = false,
              type     = "number",
            },
          },
          {
            authenticated_groups_claim = {
              required = false,
              type     = "array",
              elements = {
                type = "string",
              },
            },
          },
          {
            authorization_endpoint = typedefs.url {
              required = false,
            },
          },
          {
            authorization_query_args_names = {
              required = false,
              type     = "array",
              elements = {
                type   = "string",
              },
            },
          },
          {
            authorization_query_args_values = {
              required = false,
              type     = "array",
              elements = {
                type   = "string",
              },
            },
          },
          {
            authorization_query_args_client = {
              required = false,
              type     = "array",
              elements = {
                type   = "string",
              },
            },
          },
          {
            authorization_rolling_timeout = {
              required = false,
              type     = "number",
              default  = 600,
            },
          },
          {
            authorization_cookie_name = {
              required = false,
              type     = "string",
              default  = "authorization",
            },
          },
          {
            authorization_cookie_path = typedefs.path {
              required = false,
              default  = "/",
            },
          },
          {
            authorization_cookie_domain = {
              required = false,
              type     = "string",
            },
          },
          {
            authorization_cookie_same_site = {
              required = false,
              type     = "string",
              default  = "Default",
              one_of   = {
                "Strict",
                "Lax",
                "None",
                "Default",
              },
            },
          },
          {
            authorization_cookie_http_only = {
              required = false,
              type     = "boolean",
              default  = true,
            },
          },
          {
            authorization_cookie_secure = {
              required = false,
              type     = "boolean",
            },
          },
          {
            preserve_query_args = {
              required = false,
              type     = "boolean",
              default  = false,
            },
          },
          {
            token_endpoint = typedefs.url {
              required = false,
            },
          },
          {
            token_endpoint_auth_method = {
              required = false,
              type     = "string",
              one_of   = {
                "client_secret_basic",
                "client_secret_post",
                "client_secret_jwt",
                "private_key_jwt",
                "none",
              },
            },
          },
          {
            token_headers_names = {
              required = false,
              type     = "array",
              elements = {
                type   = "string",
              },
            },
          },
          {
            token_headers_values = {
              required = false,
              type     = "array",
              elements = {
                type   = "string",
              },
            },
          },
          {
            token_headers_client = {
              required = false,
              type     = "array",
              elements = {
                type   = "string",
              },
            },
          },
          {
            token_headers_replay = {
              required = false,
              type     = "array",
              elements = {
                type   = "string",
              },
            },
          },
          {
            token_headers_prefix = {
              required = false,
              type     = "string",
            },
          },
          {
            token_headers_grants = {
              required = false,
              type     = "array",
              elements = {
                type   = "string",
                one_of = {
                  "password",
                  "client_credentials",
                  "authorization_code",
                  "refresh_token",
                },
              },
            },
          },
          {
            token_post_args_names = {
              required = false,
              type     = "array",
              elements = {
                type   = "string",
              },
            },
          },
          {
            token_post_args_values = {
              required = false,
              type     = "array",
              elements = {
                type   = "string",
              },
            },
          },
          {
            token_post_args_client = {
              required = false,
              type     = "array",
              elements = {
                type   = "string",
              },
            },
          },
          {
            introspection_endpoint = typedefs.url {
              required = false,
            },
          },
          {
            introspection_endpoint_auth_method = {
              required = false,
              type     = "string",
              one_of   = {
                "client_secret_basic",
                "client_secret_post",
                "client_secret_jwt",
                "private_key_jwt",
                "none",
              },
            },
          },
          {
            introspection_hint = {
              required = false,
              type     = "string",
              default  = "access_token",
            },
          },
          {
            introspection_check_active = {
              required = false,
              type     = "boolean",
              default  = true,
            },
          },
          {
            introspection_accept = {
              required = false,
              type     = "string",
              default  = "application/json",
              one_of   = {
                "application/json",
                "application/token-introspection+jwt",
                "application/jwt",
              },
            },
          },
          {
            introspection_headers_names = {
              required = false,
              type     = "array",
              elements = {
                type   = "string",
              },
            },
          },
          {
            introspection_headers_values = {
              required = false,
              type     = "array",
              elements = {
                type   = "string",
              },
            },
          },
          {
            introspection_headers_client = {
              required = false,
              type     = "array",
              elements = {
                type   = "string",
              },
            },
          },
          {
            introspection_post_args_names = {
              required = false,
              type     = "array",
              elements = {
                type   = "string",
              },
            },
          },
          {
            introspection_post_args_values = {
              required = false,
              type     = "array",
              elements = {
                type   = "string",
              },
            },
          },
          {
            introspection_post_args_client = {
              required = false,
              type     = "array",
              elements = {
                type   = "string",
              },
            },
          },
          {
            introspect_jwt_tokens = {
              required = false,
              type     = "boolean",
              default  = false,
            },
          },
          {
            revocation_endpoint = typedefs.url {
              required = false,
            },
          },
          {
            revocation_endpoint_auth_method = {
              required = false,
              type     = "string",
              one_of   = {
                "client_secret_basic",
                "client_secret_post",
                "client_secret_jwt",
                "private_key_jwt",
                "none",
              },
            },
          },
          {
            end_session_endpoint = typedefs.url {
              required = false,
            },
          },
          {
            userinfo_endpoint = typedefs.url {
              required = false,
            },
          },
          {
            userinfo_accept = {
              required = false,
              type     = "string",
              default  = "application/json",
              one_of   = {
                "application/json",
                "application/jwt",
              },
            },
          },
          {
            userinfo_headers_names = {
              required = false,
              type     = "array",
              elements = {
                type   = "string",
              },
            },
          },
          {
            userinfo_headers_values = {
              required = false,
              type     = "array",
              elements = {
                type   = "string",
              },
            },
          },
          {
            userinfo_headers_client = {
              required = false,
              type     = "array",
              elements = {
                type   = "string",
              },
            },
          },
          {
            userinfo_query_args_names = {
              required = false,
              type     = "array",
              elements = {
                type   = "string",
              },
            },
          },
          {
            userinfo_query_args_values = {
              required = false,
              type     = "array",
              elements = {
                type   = "string",
              },
            },
          },
          {
            userinfo_query_args_client = {
              required = false,
              type     = "array",
              elements = {
                type   = "string",
              },
            },
          },
          {
            token_exchange_endpoint = typedefs.url {
              required = false,
            },
          },
          {
            session_secret = {
              required = false,
              type     = "string",
              encrypted = true,
              referenceable = true,
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
          {
            reverify = {
              required = false,
              type     = "boolean",
              default  = false,
            },
          },
          {
            jwt_session_claim = {
              required = false,
              type     = "string",
              default  = "sid",
            },
          },
          {
            jwt_session_cookie = {
              required = false,
              type     = "string",
            },
          },
          {
            bearer_token_param_type = {
              required = false,
              type     = "array",
              default  = {
                "header",
                "query",
                "body",
              },
              elements = {
                type   = "string",
                one_of = {
                  "header",
                  "cookie",
                  "query",
                  "body",
                },
              },
            },
          },
          {
            bearer_token_cookie_name = {
              required = false,
              type     = "string",
            },
          },
          {
            client_credentials_param_type = {
              required = false,
              type     = "array",
              default  = {
                "header",
                "query",
                "body",
              },
              elements = {
                type   = "string",
                one_of = {
                  "header",
                  "query",
                  "body",
                },
              },
            },
          },
          {
            password_param_type = {
              required = false,
              type     = "array",
              default  = {
                "header",
                "query",
                "body",
              },
              elements = {
                type   = "string",
                one_of = {
                  "header",
                  "query",
                  "body",
                },
              },
            },
          },
          {
            id_token_param_type = {
              required = false,
              type     = "array",
              default  = {
                "header",
                "query",
                "body",
              },
              elements = {
                type   = "string",
                one_of = {
                  "header",
                  "query",
                  "body",
                },
              },
            },
          },
          {
            id_token_param_name = {
              required = false,
              type     = "string",
            },
          },
          {
            refresh_token_param_type = {
              required = false,
              type     = "array",
              default  = {
                "header",
                "query",
                "body",
              },
              elements = {
                type   = "string",
                one_of = {
                  "header",
                  "query",
                  "body",
                },
              },
            },
          },
          {
            refresh_token_param_name = {
              required = false,
              type     = "string",
            },
          },
          {
            refresh_tokens = {
              required = false,
              type     = "boolean",
              default  = true,
            },
          },
          {
            upstream_headers_claims = {
              required = false,
              type     = "array",
              elements = {
                type   = "string",
              },
            },
          },
          {
            upstream_headers_names = {
              required = false,
              type     = "array",
              elements = {
                type   = "string",
              },
            },
          },
          {
            upstream_access_token_header = {
              required = false,
              type     = "string",
              default  = "authorization:bearer",
            },
          },
          {
            upstream_access_token_jwk_header = {
              required = false,
              type     = "string",
            },
          },
          {
            upstream_id_token_header = {
              required = false,
              type     = "string",
            },
          },
          {
            upstream_id_token_jwk_header = {
              required = false,
              type     = "string",
            },
          },
          {
            upstream_refresh_token_header = {
              required = false,
              type     = "string",
            },
          },
          {
            upstream_user_info_header = {
              required = false,
              type     = "string",
            },
          },
          {
            upstream_user_info_jwt_header = {
              required = false,
              type     = "string",
            },
          },
          {
            upstream_introspection_header = {
              required = false,
              type     = "string",
            },
          },
          {
            upstream_introspection_jwt_header = {
              required = false,
              type     = "string",
            },
          },
          {
            upstream_session_id_header = {
              required = false,
              type     = "string",
            },
          },
          {
            downstream_headers_claims = {
              required = false,
              type     = "array",
              elements = {
                type   = "string",
              },
            },
          },
          {
            downstream_headers_names = {
              required = false,
              type     = "array",
              elements = {
                type   = "string",
              },
            },
          },
          {
            downstream_access_token_header = {
              required = false,
              type     = "string",
            },
          },
          {
            downstream_access_token_jwk_header = {
              required = false,
              type     = "string",
            },
          },
          {
            downstream_id_token_header = {
              required = false,
              type     = "string",
            },
          },
          {
            downstream_id_token_jwk_header = {
              required = false,
              type     = "string",
            },
          },
          {
            downstream_refresh_token_header = {
              required = false,
              type     = "string",
            },
          },
          {
            downstream_user_info_header = {
              required = false,
              type     = "string",
            },
          },
          {
            downstream_user_info_jwt_header = {
              required = false,
              type     = "string",
            },
          },
          {
            downstream_introspection_header = {
              required = false,
              type     = "string",
            },
          },
          {
            downstream_introspection_jwt_header = {
              required = false,
              type     = "string",
            },
          },
          {
            downstream_session_id_header = {
              required = false,
              type     = "string",
            },
          },
          {
            login_methods = {
              required = false,
              type     = "array",
              default  = {
                "authorization_code",
              },
              elements = {
                type   = "string",
                one_of = {
                  "password",
                  "client_credentials",
                  "authorization_code",
                  "bearer",
                  "introspection",
                  "userinfo",
                  "kong_oauth2",
                  "refresh_token",
                  "session",
                }
              },
            },
          },
          {
            login_action = {
              required = false,
              type     = "string",
              default  = "upstream",
              one_of   = {
                "upstream",
                "response",
                "redirect",
              },
            },
          },
          {
            login_tokens = {
              required = false,
              type     = "array",
              default  = {
                "id_token",
              },
              elements = {
                type   = "string",
                one_of = {
                  "id_token",
                  "access_token",
                  "refresh_token",
                  "tokens",
                  "introspection",
                }
              },
            },
          },
          {
            login_redirect_mode = {
              required = false,
              type     = "string",
              default  = "fragment",
              one_of   = {
                "query",
                "fragment",
              },
            },
          },
          {
            logout_query_arg = {
              required = false,
              type     = "string",
            },
          },
          {
            logout_post_arg = {
              required = false,
              type     = "string",
            },
          },
          {
            logout_uri_suffix = {
              required = false,
              type     = "string",
            },
          },
          {
            logout_methods = {
              required = false,
              type     = "array",
              default  = {
                "POST",
                "DELETE",
              },
              elements = {
                type   = "string",
                one_of = {
                  "POST",
                  "GET",
                  "DELETE",
                },
              },
            },
          },
          {
            logout_revoke = {
              required = false,
              type     = "boolean",
              default  = false,
            },
          },
          {
            logout_revoke_access_token = {
              required = false,
              type     = "boolean",
              default  = true,
            },
          },
          {
            logout_revoke_refresh_token = {
              required = false,
              type     = "boolean",
              default  = true,
            },
          },
          {
            consumer_claim = {
              required = false,
              type     = "array",
              elements = {
                type   = "string",
              },
            },
          },
          {
            consumer_by = {
              required = false,
              type     = "array",
              default  = {
                "username",
                "custom_id",
              },
              elements = {
                type   = "string",
                one_of = {
                  "id",
                  "username",
                  "custom_id",
                },
              },
            },
          },
          {
            consumer_optional = {
              required = false,
              type     = "boolean",
              default  = false,
            },
          },
          {
            credential_claim = {
              required = false,
              type     = "array",
              default  = {
                "sub",
              },
              elements = {
                type   = "string",
              },
            },
          },
          {
            anonymous = {
              required = false,
              type     = "string",
            },
          },
          {
            run_on_preflight = {
              required = false,
              type     = "boolean",
              default  = true,
            },
          },
          {
            leeway = {
              required = false,
              type     = "number",
              default  = 0,
            },
          },
          {
            verify_parameters = {
              required = false,
              type     = "boolean",
              default  = false,
            },
          },
          {
            verify_nonce = {
              required = false,
              type     = "boolean",
              default  = true,
            },
          },
          {
            verify_claims = {
              required = false,
              type     = "boolean",
              default  = true,
            },
          },
          {
            verify_signature = {
              required = false,
              type     = "boolean",
              default  = true,
            },
          },
          {
            ignore_signature = {
              required = false,
              type     = "array",
              default  = {
              },
              elements = {
                type   = "string",
                one_of = {
                  "password",
                  "client_credentials",
                  "authorization_code",
                  "refresh_token",
                  "session",
                  "introspection",
                  "userinfo",
                },
              },
            },
          },
          {
            enable_hs_signatures = {
              required = false,
              type     = "boolean",
              default  = false,
            },
          },
          {
            disable_session = {
              required = false,
              type     = "array",
              elements = {
                type   = "string",
                one_of = {
                  "password",
                  "client_credentials",
                  "authorization_code",
                  "bearer",
                  "introspection",
                  "userinfo",
                  "kong_oauth2",
                  "refresh_token",
                  "session",
                },
              },
            },
          },
          {
            cache_ttl = {
              required = false,
              type     = "number",
              default  = 3600,
            },
          },
          {
            cache_ttl_max = {
              required = false,
              type     = "number",
            },
          },
          {
            cache_ttl_min = {
              required = false,
              type     = "number",
            },
          },
          {
            cache_ttl_neg = {
              required = false,
              type     = "number",
            },
          },
          {
            cache_ttl_resurrect = {
              required = false,
              type     = "number",
            },
          },
          {
            cache_tokens = {
              required = false,
              type     = "boolean",
              default  = true,
            },
          },
          {
            cache_tokens_salt = {
              required = false,
              type     = "string",
              auto     = true,
            },
          },
          {
            cache_introspection = {
              required = false,
              type     = "boolean",
              default  = true,
            },
          },
          {
            cache_token_exchange = {
              required = false,
              type     = "boolean",
              default  = true,
            },
          },
          {
            cache_user_info = {
              required = false,
              type     = "boolean",
              default  = true,
            },
          },
          {
            search_user_info = {
              required = false,
              type     = "boolean",
              default  = false,
            },
          },
          {
            hide_credentials = {
              required = false,
              type     = "boolean",
              default  = false,
            },
          },
          {
            http_version = {
              required = false,
              type     = "number",
              default  = 1.1,
              custom_validator = function(v)
                if v == 1.0 or v == 1.1 then
                  return true
                end

                return nil, "must be 1.0 or 1.1"
              end
            },
          },
          {
            http_proxy = typedefs.url {
              required = false,
            },
          },
          {
            http_proxy_authorization = {
              required = false,
              type     = "string",
            },
          },
          {
            https_proxy = typedefs.url {
              required = false,
            },
          },
          {
            https_proxy_authorization = {
              required = false,
              type     = "string",
            },
          },
          {
            no_proxy = {
              required = false,
              type     = "string",
            },
          },
          {
            keepalive = {
              required = false,
              type     = "boolean",
              default  = true,
            },
          },
          {
            ssl_verify = {
              required = false,
              type     = "boolean",
              default  = false,
            },
          },
          {
            timeout = {
              required = false,
              type     = "number",
              default  = 10000,
            },
          },
          {
            display_errors = {
              required = false,
              type     = "boolean",
              default  = false,
            },
          },
          {
            by_username_ignore_case = {
              required = false,
              type     = "boolean",
              default  = false,
            },
          },
          -- Not yet implemented
          -- {
          --   resolve_aggregated_claims = {
          --     required = false,
          --     type     = "boolean",
          --     default  = false,
          --   },
          -- },
          {
            resolve_distributed_claims = {
              required = false,
              type     = "boolean",
              default  = false,
            },
          },
        },
        shorthand_fields = {
          -- TODO: deprecated forms, to be removed in Kong 4.0
          {
            authorization_cookie_lifetime = {
              type = "number",
              func = function(value)
                return { authorization_rolling_timeout = value }
              end,
            },
          },
          {
            authorization_cookie_samesite = {
              type = "string",
              func = function(value)
                if value == "off" then
                  value = "Default"
                end
                return { authorization_cookie_same_site = value }
              end,
            },
          },
          {
            authorization_cookie_httponly = {
              type = "boolean",
              func = function(value)
                return { authorization_cookie_http_only = value }
              end,
            },
          },
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
                ngx.log(ngx.INFO, "[openid-connect] session_cookie_renew option does not exists anymore")
              end,
            },
          },
          {
            session_cookie_maxsize = {
              type = "integer",
              func = function()
                -- new library has this hard coded
                ngx.log(ngx.INFO, "[openid-connect] session_cookie_maxsize option does not exists anymore")
              end,
            },
          },
          {
            session_strategy = {
              type = "string",
              func = function()
                -- new library supports only the so called regenerate strategy
                ngx.log(ngx.INFO, "[openid-connect] session_strategy option does not exists anymore")
              end,
            },
          },
          {
            session_compressor = {
              type = "string",
              func = function()
                -- new library decides this based on data size
                ngx.log(ngx.INFO, "[openid-connect] session_compressor option does not exists anymore")
              end,
            },
          },
        },
      },
    },
  },
}


return config
