local utils     = require "kong.tools.utils"
local Errors    = require "kong.dao.errors"
local cache     = require "kong.plugins.openid-connect.cache"
local arguments = require "kong.plugins.openid-connect.arguments"


local get_phase = ngx.get_phase


local function check_user(anonymous)
  if anonymous == nil or anonymous == ngx.null or anonymous == "" or utils.is_valid_uuid(anonymous) then
    return true
  end

  return false, "the anonymous user must be empty or a valid uuid"
end


local function self_check(_, conf, _, is_update)
  if is_update then
    return true
  end

  local phase = get_phase()
  if phase == "access" or phase == "content" then
    local args = arguments(conf)

    local issuer_uri = args.get_conf_arg("issuer")
    if not issuer_uri then
      return false, "issuer was not specified"
    end

    local options = {
      http_version    = args.get_conf_arg("http_version", 1.1),
      ssl_verify      = args.get_conf_arg("ssl_verify",   true),
      timeout         = args.get_conf_arg("timeout",      10000),
      headers         = args.get_conf_args("discovery_headers_names", "discovery_headers_values"),
      extra_jwks_uris = args.get_conf_arg("extra_jwks_uris"),
    }

    local issuer = cache.issuers.load(issuer_uri, options)
    if not issuer then
      return false, Errors.schema("openid connect discovery failed")
    end
  end

  return true
end


return {
  no_consumer                          = true,
  self_check                           = self_check,
  fields                               = {
    issuer                             = {
      required                         = true,
      type                             = "url",
    },
    client_arg                         = {
      required                         = false,
      type                             = "string",
      default                          = "client_id"
    },
    client_id                          = {
      required                         = false,
      type                             = "array",
    },
    client_secret                      = {
      required                         = false,
      type                             = "array",
    },
    redirect_uri                       = {
      required                         = false,
      type                             = "array",
    },
    login_redirect_uri                 = {
      required                         = false,
      type                             = "array",
    },
    logout_redirect_uri                = {
      required                         = false,
      type                             = "array",
    },
    forbidden_redirect_uri             = {
      required                         = false,
      type                             = "array",
    },
    forbidden_error_message            = {
      required                         = false,
      type                             = "string",
      default                          = "Forbidden"
    },
    forbidden_destroy_session          = {
      required                         = false,
      type                             = "boolean",
      default                          = true,
    },
    unauthorized_redirect_uri          = {
      required                         = false,
      type                             = "array",
    },
    unauthorized_error_message         = {
      required                         = false,
      type                             = "string",
      default                          = "Unauthorized"
    },
    unexpected_redirect_uri            = {
      required                         = false,
      type                             = "array",
    },
    scopes                             = {
      required                         = false,
      type                             = "array",
      default                          = {
        "openid"
      },
    },
    scopes_required                    = {
      required                         = false,
      type                             = "array",
    },
    scopes_claim                       = {
      required                         = false,
      type                             = "array",
      default                          = {
        "scope"
      },
    },
    response_mode                      = {
      required                         = false,
      type                             = "string",
      enum                             = {
        "query",
        "form_post",
        "fragment",
      },
      default                          = "query",
    },
    auth_methods                       = {
      required                         = false,
      type                             = "array",
      enum                             = {
        "password",
        "client_credentials",
        "authorization_code",
        "bearer",
        "introspection",
        "kong_oauth2",
        "refresh_token",
        "session",
      },
      default                          = {
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
    audience                           = {
      required                         = false,
      type                             = "array",
    },
    audience_required                  = {
      required                         = false,
      type                             = "array",
    },
    audience_claim                     = {
      required                         = false,
      type                             = "array",
      default                          = {
        "aud"
      },
    },
    domains                            = {
      required                         = false,
      type                             = "array",
    },
    max_age                            = {
      required                         = false,
      type                             = "number",
    },
    authorization_cookie_name          = {
      required                         = false,
      type                             = "string",
      default                          = "authorization",
    },
    authorization_cookie_lifetime      = {
      required                         = false,
      type                             = "number",
      default                          = 600,
    },
    session_cookie_name                = {
      required                         = false,
      type                             = "string",
      default                          = "session",
    },
    session_cookie_lifetime            = {
      required                         = false,
      type                             = "number",
      default                          = 3600,
    },
    session_storage                    = {
      required                         = false,
      type                             = "string",
      enum                             = {
        "cookie",
        "memcache",
        "redis",
      },
      default                          = "cookie",
    },
    session_memcache_prefix            = {
      required                         = false,
      type                             = "string",
      default                          = "sessions"
    },
    session_memcache_socket            = {
      required                         = false,
      type                             = "string",
    },
    session_memcache_host              = {
      required                         = false,
      type                             = "string",
      default                          = "127.0.0.1",
    },
    session_memcache_port              = {
      required                         = false,
      type                             = "number",
      default                          = 11211,
    },
    session_redis_prefix               = {
      required                         = false,
      type                             = "string",
      default                          = "sessions"
    },
    session_redis_socket               = {
      required                         = false,
      type                             = "string",
    },
    session_redis_host                 = {
      required                         = false,
      type                             = "string",
      default                          = "127.0.0.1",
    },
    session_redis_port                 = {
      required                         = false,
      type                             = "number",
      default                          = 6379,
    },
    session_redis_auth                 = {
      required                         = false,
      type                             = "string",
    },
    extra_jwks_uris                    = {
      required                         = false,
      type                             = "array",
    },
    jwt_session_cookie                 = {
      required                         = false,
      type                             = "string",
    },
    jwt_session_claim                  = {
      required                         = false,
      type                             = "string",
      default                          = "sid",
    },
    reverify                           = {
      required                         = false,
      type                             = "boolean",
      default                          = false,
    },
    bearer_token_param_type            = {
      required                         = false,
      type                             = "array",
      enum                             = {
        "header",
        "query",
        "body",
      },
      default                          = {
        "header",
        "query",
        "body",
      },
    },
    client_credentials_param_type      = {
      required                         = false,
      type                             = "array",
      enum                             = {
        "header",
        "query",
        "body",
      },
      default                          = {
        "header",
        "query",
        "body",
      },
    },
    password_param_type                = {
      required                         = false,
      type                             = "array",
      enum                             = {
        "header",
        "query",
        "body",
      },
      default                          = {
        "header",
        "query",
        "body",
      },
    },
    id_token_param_name                = {
      required                         = false,
      type                             = "string",
    },
    id_token_param_type                = {
      required                         = false,
      type                             = "array",
      enum                             = {
        "header",
        "query",
        "body",
      },
      default                          = {
        "header",
        "query",
        "body",
      },
    },
    discovery_headers_names            = {
      required                         = false,
      type                             = "array",
    },
    discovery_headers_values           = {
      required                         = false,
      type                             = "array",
    },
    authorization_query_args_names     = {
      required                         = false,
      type                             = "array",
    },
    authorization_query_args_values    = {
      required                         = false,
      type                             = "array",
    },
    authorization_query_args_client    = {
      required                         = false,
      type                             = "array",
    },
    token_post_args_names              = {
      required                         = false,
      type                             = "array",
    },
    token_post_args_values             = {
      required                         = false,
      type                             = "array",
    },
    token_headers_client               = {
      required                         = false,
      type                             = "array",
    },
    token_headers_replay               = {
      required                         = false,
      type                             = "array",
    },
    token_headers_prefix               = {
      required                         = false,
      type                             = "string",
    },
    token_headers_grants               = {
      required                         = false,
      type                             = "array",
      enum                             = {
        "password",
        "client_credentials",
        "authorization_code",
      },
    },
    token_endpoint_auth_method         = {
      required                         = false,
      type                             = "string",
      enum                             = {
        "none",
        "client_secret_basic",
        "client_secret_post",
      },
    },
    upstream_headers_claims            = {
      required                         = false,
      type                             = "array",
    },
    upstream_headers_names             = {
      required                         = false,
      type                             = "array",
    },
    downstream_headers_claims          = {
      required                         = false,
      type                             = "array",
    },
    downstream_headers_names           = {
      required                         = false,
      type                             = "array",
    },
    upstream_access_token_header       = {
      required                         = false,
      type                             = "string",
      default                          = "authorization:bearer",
    },
    downstream_access_token_header     = {
      required                         = false,
      type                             = "string",
    },
    upstream_access_token_jwk_header   = {
      required                         = false,
      type                             = "string",
    },
    downstream_access_token_jwk_header = {
      required                         = false,
      type                             = "string",
    },
    upstream_id_token_header           = {
      required                         = false,
      type                             = "string",
    },
    downstream_id_token_header         = {
      required                         = false,
      type                             = "string",
    },
    upstream_id_token_jwk_header       = {
      required                         = false,
      type                             = "string",
    },
    downstream_id_token_jwk_header     = {
      required                         = false,
      type                             = "string",
    },
    upstream_refresh_token_header      = {
      required                         = false,
      type                             = "string",
    },
    downstream_refresh_token_header    = {
      required                         = false,
      type                             = "string",
    },
    upstream_user_info_header           = {
      required                         = false,
      type                             = "string",
    },
    downstream_user_info_header        = {
      required                         = false,
      type                             = "string",
    },
    upstream_introspection_header      = {
      required                         = false,
      type                             = "string",
    },
    downstream_introspection_header    = {
      required                         = false,
      type                             = "string",
    },
    introspect_jwt_tokens              = {
      required                         = false,
      type                             = "boolean",
      default                          = false,
    },
    introspection_endpoint             = {
      required                         = false,
      type                             = "url",
    },
    introspection_hint                 = {
      required                         = false,
      type                             = "string",
      default                          = "access_token",
    },
    introspection_headers_names        = {
      required                         = false,
      type                             = "array",
    },
    introspection_headers_values       = {
      required                         = false,
      type                             = "array",
    },
    login_methods                      = {
      required                         = false,
      type                             = "array",
      enum                             = {
        "password",
        "client_credentials",
        "authorization_code",
        "bearer",
        "introspection",
        "kong_oauth2",
        "session",
      },
      default                          = {
        "authorization_code",
      },
    },
    login_action                       = {
      required                         = false,
      type                             = "string",
      enum                             = {
        "upstream",
        "response",
        "redirect",
      },
      default                          = "upstream",
    },
    login_tokens                       = {
      required                         = false,
      type                             = "array",
      enum                             = {
        "id_token",
        "access_token",
        "refresh_token",
      },
      default                          = {
        "id_token",
      },
    },
    login_redirect_mode                = {
      required                         = false,
      type                             = "string",
      enum                             = {
        "query",
        --"form_post",
        "fragment",
      },
      default                          = "fragment",
    },
    logout_query_arg                   = {
      required                         = false,
      type                             = "string",
    },
    logout_post_arg                    = {
      required                         = false,
      type                             = "string",
    },
    logout_uri_suffix                  = {
      required                         = false,
      type                             = "string",
    },
    logout_methods                     = {
      type                             = "array",
      enum                             = {
        "POST",
        "GET",
        "DELETE",
      },
      default                          = {
        "POST",
        "DELETE",
      },
    },
    logout_revoke                      = {
      required                         = false,
      type                             = "boolean",
      default                          = false,
    },
    revocation_endpoint                = {
      required                         = false,
      type                             = "url",
    },
    end_session_endpoint               = {
      required                         = false,
      type                             = "url",
    },
    token_exchange_endpoint            = {
      required                         = false,
      type                             = "url",
    },
    consumer_claim                     = {
      required                         = false,
      type                             = "array",
    },
    consumer_by                        = {
      required                         = false,
      type                             = "array",
      enum                             = {
        "id",
        "username",
        "custom_id",
      },
      default                          = {
        "username",
        "custom_id",
      },
    },
    consumer_optional                  = {
      required                         = false,
      type                             = "boolean",
      default                          = false,
    },
    credential_claim                   = {
      required                         = false,
      type                             = "array",
      default                          = {
        "sub"
      },
    },
    anonymous                          = {
      required                         = false,
      type                             = "string",
      func                             = check_user,
    },
    run_on_preflight                   = {
      required                         = false,
      type                             = "boolean",
      default                          = true,
    },
    leeway                             = {
      required                         = false,
      type                             = "number",
      default                          = 0,
    },
    verify_parameters                  = {
      required                         = false,
      type                             = "boolean",
      default                          = true,
    },
    verify_nonce                       = {
      required                         = false,
      type                             = "boolean",
      default                          = true,
    },
    verify_signature                   = {
      required                         = false,
      type                             = "boolean",
      default                          = true,
    },
    verify_claims                      = {
      required                         = false,
      type                             = "boolean",
      default                          = true,
    },
    cache_introspection                = {
      required                         = false,
      type                             = "boolean",
      default                          = true,
    },
    cache_token_exchange               = {
      required                         = false,
      type                             = "boolean",
      default                          = true,
    },
    cache_tokens                       = {
      required                         = false,
      type                             = "boolean",
      default                          = true,
    },
    cache_user_info                    = {
      required                         = false,
      type                             = "boolean",
      default                          = true,
    },
    cache_ttl                          = {
      required                         = false,
      type                             = "number",
      default                          = 3600,
    },
    hide_credentials                   = {
      required                         = false,
      type                             = "boolean",
      default                          = false
    },
    http_version                       = {
      required                         = false,
      type                             = "number",
      enum                             = {
        1.0,
        1.1,
      },
      default                          = 1.1,
    },
    ssl_verify                         = {
      required                         = false,
      type                             = "boolean",
      default                          = true,
    },
    timeout                            = {
      required                         = false,
      type                             = "number",
      default                          = 10000,
    },
  },
}
