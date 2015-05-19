return {
  logging_url = { required = true, type = "string" },
  method = { require = false, default = "POST", enum = { "POST", "PUT", "PATCH" } },
  timeout = { required = false, default = 10000, type = "number" },
  keepalive = { required = false, default = 60000, type = "number" }
}
