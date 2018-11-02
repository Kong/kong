return {
  fields = {
    environment = {type = "string"},
    retry_count = {type = "number", default = 10},
    queue_size = {type = "number", default = 1000},
    flush_timeout = {type = "number", default = 2},
    log_bodies = {type = "boolean", default = false},
    service_token = {type = "string", required = true},
    connection_timeout = {type = "number", default = 30},
    host = {type = "string", required = true, default = "collector.brain.kong.com"},
    port = {type = "number", required = true, default = 443},
    https = {type = "boolean", default = true},
    https_verify = {type = "boolean", default = false}
  }
}
