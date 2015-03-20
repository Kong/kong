return {
  host = { required = true },
  port = { required = true },
  timeout = { required = false, default = 10000 },
  keepalive = { required = false, default = 60000 }
}
