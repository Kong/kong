return {
  fields = {
    es_url = { required = true, type = "url" },
    index_type = {default="log",type="string"},
    index_prefix = {default="konglog-",type="string"},
    log_bodies = {type = "boolean", default = false},
    timeout = { default = 10000, type = "number" },
    keepalive = { default = 60000, type = "number" },
  }
}
