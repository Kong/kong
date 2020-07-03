local typedefs = require "kong.db.schema.typedefs"

local severity = {
  type = "string",
  default = "info",
  one_of = { "debug", "info", "notice", "warning", "err", "crit", "alert", "emerg" },
}

local facility = {
	type = "string",
	default = "FACILITY_USER",
	one_of = { "FACILITY_AUTH", "FACILITY_AUTHPRIV",  "FACILITY_CRON",  "FACILITY_DAEMON",
			"FACILITY_FTP",  "FACILITY_KERN",  "FACILITY_LPR",  "FACILITY_MAIL",
			"FACILITY_NEWS", "FACILITY_SYSLOG",  "FACILITY_USER",  "FACILITY_UUCP",
			"FACILITY_LOCAL0",  "FACILITY_LOCAL1", "FACILITY_LOCAL2",  "FACILITY_LOCAL3",
			"FACILITY_LOCAL4",  "FACILITY_LOCAL5",  "FACILITY_LOCAL6",  "FACILITY_LOCAL7" },
}

return {
  name = "syslog",
  fields = {
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { log_level = severity },
          { successful_severity = severity },
          { client_errors_severity = severity },
          { server_errors_severity = severity },
          { syslog_facility = facility },
    }, }, },
  },
}

