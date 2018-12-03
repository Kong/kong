return {
  no_consumer = true,
  fields = {
    cookie_name = { type = "string", default = "session" },
    cookie_lifetime = { type = "number", default = 3600 },
    cookie_path = { type = "string", default = "/" },
    cookie_domain = { type = "string" },
    cookie_samesite = { 
      type = "string", 
      default = "Strict", 
      one_of = { "Strict", "Lax", "off" }
    },
    cookie_httponly = { type = "boolean", default = true },
    cookie_secure = { type = "boolean", default = true },
    storage = {
      required = false,
      type = "string",
      enum = { 
        "cookie", 
        "kong",
      },
      default = "cookie",
    },
  }
}
