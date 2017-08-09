local utils = require "kong.tools.utils"


local function check_user(anonymous)
  if anonymous == nil or anonymous == ngx.null or anonymous == "" or utils.is_valid_uuid(anonymous) then
    return true
  end

  return false, "the anonymous user must be empty or a valid uuid"
end


return {
  no_consumer               = true,
  fields                    = {
    issuer                  = {
      required              = true,
      type                  = "url",
    },
    client_id               = {
      required              = true,
      type                  = "array",
    },
    client_secret           = {
      required              = true,
      type                  = "array",
    },
    redirect_uri            = {
      required              = false,
      type                  = "array",
    },
    scopes                  = {
      required              = false,
      type                  = "array",
      default               = {
        "openid"
      },
    },
    response_mode           = {
      required              = false,
      type                  = "string",
      enum                  = {
        "query",
        "form_post",
        "fragment"
      },
      default               = "query",
    },
    auth_methods            = {
      required              = false,
      type                  = "array",
      enum                  = {
        "password",
        "client_credentials",
        "authorization_code",
        "bearer",
        "introspection",
        "kong_oauth2",
        "refresh_token",
        "session",
      },
      default               = {
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
    audience                = {
      required              = false,
      type                  = "array",
    },
    domains                 = {
      required              = false,
      type                  = "array",
    },
    max_age                 = {
      required              = false,
      type                  = "number",
    },
    reverify                = {
      required              = false,
      type                  = "boolean",
      default               = false,
    },
    access_token_jwk_header = {
      required              = false,
      type                  = "string",
    },
    id_token_param_name     = {
      required              = false,
      type                  = "string",
    },
    id_token_param_type     = {
      required              = false,
      type                  = "array",
      enum                  = {
        "query",
        "header",
        "body"
      },
      default               = {
        "query",
        "header",
        "body"
      },
    },
    id_token_header         = {
      required              = false,
      type                  = "string",
    },
    id_token_jwk_header     = {
      required              = false,
      type                  = "string",
    },
    refresh_token_header    = {
      required              = false,
      type                  = "string",
    },
    userinfo_header         = {
      required              = false,
      type                  = "string",
    },
    introspection_header    = {
      required              = false,
      type                  = "string",
    },
    introspection_endpoint  = {
      required              = false,
      type                  = "url",
    },
    login_action            = {
      required              = false,
      type                  = "string",
      enum                  = {
        "upstream",
        "response",
        "redirect",
      },
      default               = "upstream",
    },
    login_tokens            = {
      required              = false,
      type                  = "array",
      enum                  = {
        "id_token",
        "access_token",
        "refresh_token",
      },
      default               = {
        "id_token",
      },
    },
    login_redirect_uri      = {
      required              = false,
      type                  = "url",
    },
    consumer_claim          = {
      required              = false,
      type                  = "string",
    },
    consumer_by             = {
      required              = false,
      type                  = "array",
      enum                  = {
        "id",
        "username",
        "custom_id",
      },
      default               = {
        "username",
        "custom_id",
      },
    },
    anonymous               = {
      type                  = "string",
      func                  = check_user,
    },
    leeway                  = {
      required              = false,
      type                  = "number",
      default               = 0,
    },
    verify_parameters       = {
      required              = false,
      type                  = "boolean",
      default               = true,
    },
    verify_nonce            = {
      required              = false,
      type                  = "boolean",
      default               = true,
    },
    verify_signature        = {
      required              = false,
      type                  = "boolean",
      default               = true,
    },
    verify_claims           = {
      required              = false,
      type                  = "boolean",
      default               = true,
    },
    http_version            = {
      required              = false,
      type                  = "number",
      enum                  = {
        1.0,
        1.1,
      },
      default               = 1.1,
    },
    ssl_verify              = {
      required              = false,
      type                  = "boolean",
      default               = true,
    },
    timeout                 = {
      required              = false,
      type                  = "number",
      default               = 10000,
    },
  },
}
