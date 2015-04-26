return {
  host = { required = true, type = "string" },
  port = { required = true, type = "number" },
  timeout = { required = false, default = 10000, type = "number" }
}
