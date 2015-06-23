return {
  fields = {
    http_endpoint = { required = true, type = "string" },
    method = { default = "POST", enum = { "POST", "PUT", "PATCH" } },
    timeout = { default = 10000, type = "number" },
    keepalive = { default = 60000, type = "number" }
  }
}
