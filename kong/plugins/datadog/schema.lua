return {
  fields = {
    host = {required = true, type = "string", default = "localhost"},
    port = {required = true, type = "number", default = 8125},
    metrics = {required = true, type = "array", enum = {"request_count", "latency", "request_size", "status_count", "response_size"}, default = {"request_count", "latency", "request_size", "status_count", "response_size"}}, 
    timeout = {type = "number", default = 10000}
  }
}
