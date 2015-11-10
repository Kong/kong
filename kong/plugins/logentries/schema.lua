return {
  fields = {
    host = { required = true, type = "string" },
    port = { required = true, type = "number" },
    timeout = { default = 10000, type = "number" },
    keepalive = { default = 60000, type = "number" },
    flush_limit = { default = 4096, type = "number" },   -- 4KB
    drop_limit = { default = 1048576, type = "number" }, -- 1MB
  }
}
