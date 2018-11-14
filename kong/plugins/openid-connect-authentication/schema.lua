return {
  no_consumer           = true,
  fields                = {
    client_id           = {
      required          = true,
      type              = "string",
    },
    client_secret       = {
      required          = true,
      type              = "string",
    },
    issuer              = {
      required          = true,
      type              = "url",
    },
    redirect_uri        = {
      required          = false,
      type              = "url",
    },
    login_redirect_uri  = {
      required          = false,
      type              = "url",
    },
    scopes              = {
      required          = false,
      type              = "array",
      default           = {
        "openid"
      },
    },
    audience            = {
      required          = false,
      type              = "array",
    },
    domains             = {
      required          = false,
      type              = "array",
    },
    max_age             = {
      required          = false,
      type              = "number",
    },
    leeway              = {
      required          = false,
      type              = "number",
      default           = 0,
    },
    http_version        = {
      required          = false,
      type              = "number",
      enum              = {
        1.0,
        1.1
      },
      default           = 1.1,
    },
    ssl_verify          = {
      required          = false,
      type              = "boolean",
      default           = true,
    },
    timeout             = {
      required          = false,
      type              = "number",
      default           = 10000,
    },
  },
}
