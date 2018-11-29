return {
  no_consumer = true,
  fields = {
    storage = { type = "string", default = "cookie" },
    cookie_name = { type = "string", default = "session" },
    cookie_lifetime = { type = "number", default = 3600 },
    cookie_path = { type = "string", default = "/" },
    cookie_domain = { type = "string" },
    cookie_samesite = { type = "string", default = "Strict" },
    cookie_httponly = { type = "boolean", default = true },
    cookie_secure = { type = "boolean", default = true },
  }
}
