local utils = require("kong.tools.utils")


return {
  no_consumer = true,
  fields = {
    secret = { 
      type = "string", 
      required = false, 
      default = utils.random_string,
    },
    cookie_name = { type = "string", default = "session" },
    cookie_lifetime = { type = "number", default = 3600 },
    cookie_renew = { type = "number", default = 600 },
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
    logout_methods = {
      type = "array",
      enum = { "POST", "GET", "DELETE" },
      default = { "GET", "POST", "DELETE" }
    },
    logout_query_arg = { 
      required = false,
      type = "string",
      default = "session_logout",
    },
    logout_post_arg = { 
      required = false, 
      type = "string",
      default = "session_logout",
    },
  }
}
