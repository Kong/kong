return {
  fields = {
    http_endpoint = { required = true, type = "url" },
    method = { default = "POST", enum = { "POST", "PUT", "PATCH" } },
    content_type = { default = "application/json", enum = { "application/json" } },
    timeout = { default = 10000, type = "number" },
    keepalive = { default = 60000, type = "number" },

    retry_count = {type = "number", default = 10},
    queue_size = {type = "number", default = 1},
    flush_timeout = {type = "number", default = 2},
  }
}
