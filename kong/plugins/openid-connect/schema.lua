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
    client_id               = {
      required              = true,
      type                  = "string",
    },
    client_secret           = {
      required              = true,
      type                  = "string",
    },
    issuer                  = {
      required              = true,
      type                  = "url",
    },
    redirect_uri            = {
      required              = false,
      type                  = "url",
    },
    scopes                  = {
      required              = false,
      type                  = "array",
      default               = { "openid" },
    },
    auth_methods            = {
      required              = false,
      type                  = "array",
      enum                  = { "password", "client_credentials", "authorization_code", "bearer", "introspection" },
      default               = { "password", "client_credentials", "authorization_code", "bearer", "introspection" },
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
      enum                  = { "query", "header", "body" },
      default               = { "query", "header", "body" },
    },
    id_token_header         = {
      required              = false,
      type                  = "string",
    },
    id_token_jwk_header     = {
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
    login_redirect_uri      = {
      required              = false,
      type                  = "url",
    },
    login_redirect_tokens   = {
      required              = false,
      type                  = "array",
      enum                  = { "id_token", "access_token", "refresh_token" },
      default               = { "id_token" },
    },
    logout_redirect_uri     = {
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
      enum                  = { "id", "username", "custom_id" },
      default               = { "username", "custom_id" }
    },
    consumer_ttl            = {
      required              = false,
      type                  = "number",
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
      enum                  = { 1.0, 1.1 },
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
