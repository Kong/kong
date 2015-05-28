return {
  service_token = { type = "string", required = true },
  batch_size = { type = "number", default = 100 },
  log_body = { type = "boolean", default = false }
}
