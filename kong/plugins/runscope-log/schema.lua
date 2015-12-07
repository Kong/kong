return {
  fields = {
    http_endpoint = { required = true, type = "url" },
    method = { default = "POST", enum = { "POST", "PUT", "PATCH" } },
    timeout = { default = 10000, type = "number" },
    keepalive = { default = 60000, type = "number" },
    access_token = { required = true, default = "", type = "string" },
    log_body = { default = false, type="boolean" }
  }
}
