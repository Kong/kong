local utils = require "kong.tools.utils"


local function check_user(anonymous)
  if anonymous == nil or anonymous == "" or utils.is_valid_uuid(anonymous) then
    return true
  end

  return false, "the anonymous user must be empty or a valid uuid"
end


return {
  no_consumer         = true,
  fields              = {
    issuer            = {
      required        = true,
      type            = "url",
    },
    tokens            = {
      required        = false,
      type            = "array",
      enum            = {
        "id_token",
        "access_token",
      },
      default         = {
        "id_token",
      },
    },
    param_name        = {
      required        = false,
      type            = "string",
      default         = "id_token",
    },
    param_type        = {
      required        = false,
      type            = "array",
      enum            = {
        "query",
        "header",
        "body",
      },
      default         = {
        "query",
        "header",
        "body",
      },
    },
    jwks_header       = {
      required        = false,
      type            = "string",
    },
    claims            = {
      required        = false,
      type            = "array",
      enum            = {
        "iss",
        "sub",
        "aud",
        "azp",
        "exp",
        "iat",
        "auth_time",
        "at_hash",
        "alg",
        "nbf",
        "hd",
      },
      default         = {
        "iss",
        "sub",
        "aud",
        "azp",
        "exp",
      },
    },
    clients           = {
      required        = false,
      type            = "array",
    },
    audience          = {
      required        = false,
      type            = "array",
    },
    domains           = {
      required        = false,
      type            = "array",
    },
    max_age           = {
      required        = false,
      type            = "number",
    },
    session_cookie    = {
      required        = false,
      type            = "string",
    },
    session_claim     = {
      required        = false,
      type            = "string",
      default         = "sid",
    },
    consumer_claim    = {
      required        = false,
      type            = "string",
    },
    consumer_by       = {
      required        = false,
      type            = "array",
      enum            = {
        "id",
        "username",
        "custom_id",
      },
      default         = {
        "custom_id",
      }
    },
    anonymous         = {
      type            = "string",
      func            = check_user,
    },
    leeway            = {
      required        = false,
      type            = "number",
      default         = 0,
    },
    http_version      = {
      required        = false,
      type            = "number",
      enum            = {
        1.0,
        1.1,
      },
      default         = 1.1,
    },
    ssl_verify        = {
      required        = false,
      type            = "boolean",
      default         = true,
    },
    timeout           = {
      required        = false,
      type            = "number",
      default         = 10000,
    },
    verify_signature  = {
      required        = false,
      type            = "boolean",
      default         = true,
    },
    verify_claims     = {
      required        = false,
      type            = "boolean",
      default         = true,
    },
  },
}
