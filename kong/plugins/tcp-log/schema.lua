return {
  fields = {
    host = { required = true, type = "string" },
    port = { required = true, type = "number" },
    timeout = { default = 10000, type = "number" },
    keepalive = { default = 60000, type = "number" },
    log_body = { default = false, type = "boolean" },
    max_body_size = { default = 65536, type = "number" }
  }
}