local ALLOWED_LEVELS = { "debug", "info", "notice", "warning", "err", "crit", "alert", "emerg" }

return {
  fields = {
    log_level = { type = "string", enum = ALLOWED_LEVELS, default = "info" },
    successful_severity = { type = "string", enum = ALLOWED_LEVELS, default = "info" },
    client_errors_severity = { type = "string", enum = ALLOWED_LEVELS, default = "info" },
    server_errors_severity = { type = "string", enum = ALLOWED_LEVELS, default = "info" },
  }
}
