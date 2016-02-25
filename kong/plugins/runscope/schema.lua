return {
  fields = {
    api_endpoint = {required = true, type = "url", default = "https://api.runscope.com"},
    bucket_key = {required = true, type = "string"},
    access_token = {required = true, default = "", type = "string"},
    timeout = {default = 10000, type = "number"},
    keepalive = {default = 30, type = "number"},
    log_body = {default = false, type = "boolean"}
  }
}
