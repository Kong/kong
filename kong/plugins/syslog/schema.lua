-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"

local severity = {
  type = "string",
  default = "info",
  required = true,
  one_of = { "debug", "info", "notice", "warning",
             "err", "crit", "alert", "emerg" }
}

local facility = { description = "The facility is used by the operating system to decide how to handle each log message.", type = "string",
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
