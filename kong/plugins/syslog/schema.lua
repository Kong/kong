local typedefs = require "kong.db.schema.typedefs"

local severity = {
  type = "string",
  default = "info",
  one_of = { "debug", "info", "notice", "warning", "err", "crit", "alert", "emerg" },
}

local facility = {
  type = "string",
  default = "USER",
  one_of = { "AUTH", "AUTHPRIV",  "CRON",  "DAEMON",
  "FTP",  "KERN",  "LPR",  "MAIL",
  "NEWS", "SYSLOG",  "USER",  "UUCP",
  "LOCAL0",  "LOCAL1", "LOCAL2",  "LOCAL3",
  "LOCAL4",  "LOCAL5",  "LOCAL6",  "LOCAL7" },
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
          { syslog_facility = facility },
    }, }, },
  },
}

