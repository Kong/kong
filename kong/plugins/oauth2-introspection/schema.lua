return {
  no_consumer = true,
  fields = {
    introspection_url = {type = "url", required = true},
    ttl = {type = "number", default = 30},
    token_type_hint = {type = "string"},
    authorization_value = {type = "string", required = true},
    timeout = {default = 10000, type = "number"},
    keepalive = {default = 60000, type = "number"},
    hide_credentials = { type = "boolean", default = false },
  }
}
