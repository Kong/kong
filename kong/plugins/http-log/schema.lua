local typedefs = require "kong.db.schema.typedefs"
local url = require "socket.url"


return {
  name = "http-log",
  fields = {
    { protocols = typedefs.protocols },
    { config = {
        type = "record",
        fields = {
          { http_endpoint = typedefs.url({ required = true, encrypted = true, referenceable = true }) }, -- encrypted = true is a Kong-Enterprise exclusive feature, does nothing in Kong CE
          { method = { description = "An optional method used to send data to the HTTP server. Supported values are `POST` (default), `PUT`, and `PATCH`.", type = "string", default = "POST", one_of = { "POST", "PUT", "PATCH" }, }, },
          { content_type = { description = "Indicates the type of data sent. The only available option is `application/json`.", type = "string", default = "application/json", one_of = { "application/json", "application/json; charset=utf-8" }, }, },
          { timeout = { description = "An optional timeout in milliseconds when sending data to the upstream server.", type = "number", default = 10000 }, },
          { keepalive = { description = "An optional value in milliseconds that defines how long an idle connection will live before being closed.", type = "number", default = 60000 }, },
          { retry_count = {
              description = "Number of times to retry when sending data to the upstream server.",
              type = "integer",
              deprecation = {
                message = "http-log: config.retry_count no longer works, please use config.queue.max_retry_time instead",
                removal_in_version = "4.0",
                old_default = 10 }, }, },
          { queue_size = {
              description = "Maximum number of log entries to be sent on each message to the upstream server.",
              type = "integer",
              deprecation = {
                message = "http-log: config.queue_size is deprecated, please use config.queue.max_batch_size instead",
                removal_in_version = "4.0",
                old_default = 1 }, }, },
          { flush_timeout = {
              description = "Optional time in seconds. If `queue_size` > 1, this is the max idle time before sending a log with less than `queue_size` records.",
              type = "number",
              deprecation = {
                message = "http-log: config.flush_timeout is deprecated, please use config.queue.max_coalescing_delay instead",
                removal_in_version = "4.0",
                old_default = 2 }, }, },
          { headers = { description = "An optional table of headers included in the HTTP message to the upstream server. Values are indexed by header name, and each header name accepts a single string.", type = "map",
            keys = typedefs.header_name {
              match_none = {
                {
                  pattern = "^[Hh][Oo][Ss][Tt]$",
                  err = "cannot contain 'Host' header",
                },
                {
                  pattern = "^[Cc][Oo][Nn][Tt][Ee][Nn][Tt]%-[Ll][Ee][nn][Gg][Tt][Hh]$",
                  err = "cannot contain 'Content-Length' header",
                },
                {
                  pattern = "^[Cc][Oo][Nn][Tt][Ee][Nn][Tt]%-[Tt][Yy][Pp][Ee]$",
                  err = "cannot contain 'Content-Type' header",
                },
              },
            },
            values = {
              type = "string",
              referenceable = true,
            },
          }},
          { queue = typedefs.queue },
          { custom_fields_by_lua = typedefs.lua_code },
        },
        custom_validator = function(config)
          -- check no double userinfo + authorization header
          local parsed_url = url.parse(config.http_endpoint)
          if parsed_url.userinfo and config.headers and config.headers ~= ngx.null then
            for hname, hvalue in pairs(config.headers) do
              if hname:lower() == "authorization" then
                return false, "specifying both an 'Authorization' header and user info in 'http_endpoint' is not allowed"
              end
            end
          end
          return true
        end,
      },
    },
  },
}
