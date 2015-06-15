return {
  fields = {
    origin = { type = "string" },
    headers = { type = "string" },
    exposed_headers = { type = "string" },
    methods = { type = "string" },
    max_age = { type = "number" },
    credentials = { type = "boolean", default = false },
    preflight_continue = { type = "boolean", default = false }
  }
}
