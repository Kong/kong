local ALLOWED_LEVELS = { "debug", "info", "notice", "warning", "err", "crit", "alert", "emerg" }

return {
  fields = {
    host = { type = "string", default = "logs-01.loggly.com" },
    port = { type = "number", default = 514 },
    key = { required = true, type = "string"},
    tags = {type = "array", default = { "kong" }},
    log_level = { type = "string", enum = ALLOWED_LEVELS, default = "info" },
    successful_severity = { type = "string", enum = ALLOWED_LEVELS, default = "info" },
    client_errors_severity = { type = "string", enum = ALLOWED_LEVELS, default = "info" },
    server_errors_severity = { type = "string", enum = ALLOWED_LEVELS, default = "info" },
    timeout = { type = "number", default = 10000 }
  }
}
