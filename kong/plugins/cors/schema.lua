return {
  origin = { type = "string" },
  headers = { type = "string" },
  methods = { type = "string" },
  max_age = { type = "number" },
  allow_credentials = { type = "boolean", default = false },
  preflight_continue = { type = "boolean", default = false }
}
