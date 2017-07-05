return {
  no_consumer = true,
  fields      = {
    issuer        = {
      required    = true,
      type        = "url",
    },
    leeway        = {
      required    = false,
      type        = "number",
      default     = 0,
    },
    http_version  = {
      required    = false,
      type        = "number",
      enum        = { 1.0, 1.1 },
      default     = 1.1,
    },
    ssl_verify    = {
      required    = false,
      type        = "boolean",
      default     = true,
    },
    timeout       = {
      required    = false,
      type        = "number",
      default     = 10000,
    },
  },
}
