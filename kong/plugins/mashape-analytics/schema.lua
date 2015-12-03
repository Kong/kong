return {
  fields = {
    service_token = {type = "string", required = true},
    environment = {type = "string"},
    batch_size = {type = "number", default = 100},
    log_body = {type = "boolean", default = false},
    delay = {type = "number", default = 2},
    max_sending_queue_size = {type = "number", default = 10}, -- in mb
    host = {required = true, type = "string", default = "socket.analytics.mashape.com"},
    port = {required = true, type = "number", default = 80},
    path = {required = true, type = "string", default = "/1.0.0/batch"}
  }
}
