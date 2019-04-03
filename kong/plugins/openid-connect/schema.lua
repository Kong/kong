local typedefs  = require "kong.db.schema.typedefs"
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

  local options = {
    http_version              = args.get_conf_arg("http_version", 1.1),
    http_proxy                = args.get_conf_arg("http_proxy"),
    http_proxy_authorization  = args.get_conf_arg("http_proxy_authorization"),
    https_proxy               = args.get_conf_arg("https_proxy"),
    https_proxy_authorization = args.get_conf_arg("https_proxy_authorization"),
    no_proxy                  = args.get_conf_arg("no_proxy"),
    keepalive                 = args.get_conf_arg("keepalive", true),
    ssl_verify                = args.get_conf_arg("ssl_verify", true),
    timeout                   = args.get_conf_arg("timeout", 10000),
    extra_jwks_uris           = args.get_conf_arg("extra_jwks_uris"),
    headers                   = args.get_conf_args("discovery_headers_names", "discovery_headers_values"),
  }

  local issuer = cache.issuers.load(issuer_uri, options)
  if not issuer then
    return false, "openid connect discovery failed"
  end

  return true
end


return {
  name = "openid-connect",
  fields = {
    { consumer  = typedefs.no_consumer    },
    { run_on    = typedefs.run_on_first   },
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
            client_arg = {
              required = false,
              type     = "string",
              default  = "client_id",
            },
          },
          {
            client_id = {
              required = false,
              type     = "array",
              elements = {
                type = "string",
              },
            },
          },
          {
            client_secret = {
              required = false,
              type     = "array",
              elements = {
                type = "string",
              },
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
            auth_methods = {
              required = false,
              type     = "array",
              default  = {
                "password",
                "client_credentials",
                "authorization_code",
                "bearer",
                "introspection",
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
                  "kong_oauth2",
                  "refresh_token",
                  "session",
                },
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
            authorization_cookie_name = {
              required = false,
              type     = "string",
              default  = "authorization",
            },
          },
          {
            authorization_cookie_lifetime = {
              required = false,
              type     = "number",
              default  = 600,
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
            authorization_cookie_samesite = {
              required = false,
              type     = "string",
              default  = "off",
              one_of   = {
                "Strict",
                "Lax",
                "off",
              },
            },
          },
          {
            authorization_cookie_httponly = {
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
            authorization_endpoint = typedefs.url {
              required = false,
            },
          },
          {
            session_secret = {
              required = false,
              type     = "string",
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
            session_redis_auth = {
              required = false,
              type     = "string",
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
            jwt_session_cookie = {
              required = false,
              type     = "string",
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
            rediscovery_lifetime = {
              required = false,
              type     = "number",
              default  = 300,
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
                  "query",
                  "body",
                },
              },
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
            id_token_param_name = {
              required = false,
              type     = "string",
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
            refresh_token_param_name = {
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
            refresh_tokens = {
              required = false,
              type     = "boolean",
              default  = true,
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
                },
              },
            },
          },
          {
            token_endpoint_auth_method = {
              required = false,
              type     = "string",
              one_of   = {
                "none",
                "client_secret_basic",
                "client_secret_post",
              },
            },
          },
          {
            token_endpoint = typedefs.url {
              required = false,
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
            upstream_access_token_header = {
              required = false,
              type     = "string",
              default  = "authorization:bearer",
            },
          },
          {
            downstream_access_token_header = {
              required = false,
              type     = "string",
            },
          },
          {
            upstream_access_token_jwk_header = {
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
            upstream_id_token_header = {
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
            upstream_id_token_jwk_header = {
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
            upstream_refresh_token_header = {
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
            upstream_user_info_header = {
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
            upstream_introspection_header = {
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
            upstream_session_id_header = {
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
            introspect_jwt_tokens = {
              required = false,
              type     = "boolean",
              default  = false,
            },
          },
          {
            introspection_endpoint = typedefs.url {
              required = false,
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
            revocation_endpoint = typedefs.url {
              required = false,
            },
          },
          {
            end_session_endpoint = typedefs.url {
              required = false,
            },
          },
          {
            token_exchange_endpoint = typedefs.url {
              required = false,
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
              uuid     = true,
              legacy   = true,
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
              default  = true,
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
            verify_signature = {
              required = false,
              type     = "boolean",
              default  = true,
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
        },
      },
    },
  },
}
