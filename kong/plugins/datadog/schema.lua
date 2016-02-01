return {
  fields = {
    host = {required = true, type = "string", default = "localhost"},
    port = {required = true, type = "number", default = 8125},
    metrics = {required = true, type = "array", enum = {"request_count", "latency", "request_size", "status_count"}, default = {"request_count", "latency", "request_size", "status_count"}}, 
    timeout = {type = "number", default = 10000}
  }
}
