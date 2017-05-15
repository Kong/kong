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
      required   = false,
      type       = "array",
      enum       = { "iss", "sub", "aud", "exp", "iat", "auth_time", "azp", "at_hash", "alg", "nbf", "hd" },
      default    = { "iss", "sub", "aud", "exp", "iat" },
    },
    param_name   = {
      required   = false,
      type       = "string",
      default    = "id_token",
    },
    param_type   = {
      required   = false,
      type       = "array",
      enum       = { "header", "query", "form", "body" },
      default    = { "header", "query", "form" },
    },
    domains      = {
      required   = false,
      type       = "array",
    },
    max_age      = {
      required   = false,
      type       = "number",
    },
    leeway       = {
      required   = false,
      type       = "number",
      default    = 0,
    },
    http_version = {
      required   = false,
      type       = "number",
      enum       = { 1.0, 1.1 },
      default    = 1.1,
    },
    ssl_verify   = {
      required   = false,
      type       = "boolean",
      default    = true,
    },
    timeout      = {
      required   = false,
      type       = "number",
      default    = 10000,
    },
  },
}
