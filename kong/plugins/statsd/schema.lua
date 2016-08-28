local metrics = {
  "request_count",
  "latency",
  "request_size",
  "status_count",
  "response_size",
  "unique_users",
  "request_per_user",
  "upstream_latency"
}

return {
  fields = {
    host = {required = true, type = "string", default = "localhost"},
    port = {required = true, type = "number", default = 8125},
    metrics = {
      type = "array",
      required = true,
      default = metrics,
      enum = metrics
    },
    timeout = {type = "number", default = 10000}
  }
}
