local typedefs = require "kong.db.schema.typedefs"

local severity = {
  type = "string",
  default = "info",
  required = true,
  one_of = { "debug", "info", "notice", "warning",
             "err", "crit", "alert", "emerg" },
}

local facility = {
  type = "string",
  default = "user",
  required = true,
  one_of = { "auth", "authpriv", "cron", "daemon",
             "ftp", "kern", "lpr", "mail",
             "news", "syslog", "user", "uucp",
             "local0", "local1", "local2", "local3",
             "local4", "local5", "local6", "local7" },
}

return {
  name = "syslog",
  fields = {
    { protocols = typedefs.protocols },
    { config = {
        type = "record",
        fields = {
          { log_level = severity },
          { successful_severity = severity },
          { client_errors_severity = severity },
          { server_errors_severity = severity },
          { custom_fields_by_lua = typedefs.lua_code },
          { facility = facility },
    }, }, },
  },
}
