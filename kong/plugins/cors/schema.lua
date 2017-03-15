return {
  no_consumer = true,
  fields = {
    origins = { type = "array" },
    headers = { type = "array" },
    exposed_headers = { type = "array" },
    methods = { type = "array", enum = { "HEAD", "GET", "POST", "PUT", "PATCH", "DELETE" } },
    max_age = { type = "number" },
    credentials = { type = "boolean", default = false },
    preflight_continue = { type = "boolean", default = false }
  }
}
