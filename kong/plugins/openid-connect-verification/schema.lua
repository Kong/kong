return {
  no_consumer    = true,
  fields         = {
    issuer       = {
      required   = true,
      type       = "url",
    },
    audiences    = {
      required   = false,
      type       = "array",
    },
    claims       = {
      required   = true,
      type       = "array",
      enum       = { "alg", "iss", "sub", "aud", "exp", "iat", "nbf", "auth_time", "azp", "at_hash" },
      default    = { "alg", "iss", "sub", "aud", "exp", "iat" },
    },
    param_name   = {
      required   = true,
      type       = "string",
      default    = "id_token",
    },
    param_type   = {
      required   = true,
      type       = "array",
      enum       = { "header", "query", "form", "body" },
      default    = { "header", "query", "form" },
    },
    domain       = {
      required   = false,
      type       = "string",
    },
    max_age      = {
      required   = false,
      type       = "number",
    },
    leeway       = {
      required   = true,
      type       = "number",
      default    = 0,
    },
    http_version = {
      required   = true,
      type       = "number",
      enum       = { 1.0, 1.1 },
      default    = 1.1,
    },
    ssl_verify   = {
      required   = true,
      type       = "boolean",
      default    = false,
    },
    timeout      = {
      required   = true,
      type       = "number",
      default    = 10000,
    },
  },
}
