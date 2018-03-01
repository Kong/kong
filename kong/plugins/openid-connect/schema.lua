local utils = require "kong.tools.utils"


local function check_user(anonymous)
  if anonymous == nil or anonymous == ngx.null or anonymous == "" or utils.is_valid_uuid(anonymous) then
    return true
  end

  return false, "the anonymous user must be empty or a valid uuid"
end


return {
  no_consumer                          = true,
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
    session_cookie_name                = {
      required                         = false,
      type                             = "string",
      default                          = "session",
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
    id_token_param_name                = {
      required                         = false,
      type                             = "string",
    },
    id_token_param_type                = {
      required                         = false,
      type                             = "array",
      enum                             = {
        "query",
        "header",
        "body",
      },
      default                          = {
        "query",
        "header",
        "body",
      },
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
    introspection_endpoint             = {
      required                         = false,
      type                             = "url",
    },
    introspection_hint                 = {
      required                         = false,
      type                             = "string",
      default                          = "access_token",
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
    consumer_claim                     = {
      required                         = false,
      type                             = "string",
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
    anonymous                          = {
      required                         = false,
      type                             = "string",
      func                             = check_user,
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
