return {
  name = "collector",
  fields = {
    {
      config = {
        type = "record",
        fields = {
          { retry_count = { type = "number", default = 10 } },
          { queue_size = { type = "number", default = 100 } },
          { flush_timeout = { type = "number", default = 1 } },
          { log_bodies = { type = "boolean", default = true } },
          { http_endpoint = { type = "string", required = true, default = "http://collector.com" } },
          { https_verify = { type = "boolean", default = false } },
        },
      },
    },
  },
}
