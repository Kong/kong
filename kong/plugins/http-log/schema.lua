local typedefs = require "kong.db.schema.typedefs"
local url = require "socket.url"
local deprecation = require("kong.deprecation")


return {
  name = "http-log",
  fields = {
    { protocols = typedefs.protocols },
    { config = {
        type = "record",
        fields = {
          { http_endpoint = typedefs.url({ required = true, encrypted = true, referenceable = true }) }, -- encrypted = true is a Kong-Enterprise exclusive feature, does nothing in Kong CE
          { method = { type = "string", default = "POST", one_of = { "POST", "PUT", "PATCH" }, }, },
          { content_type = { type = "string", default = "application/json", one_of = { "application/json", "application/json; charset=utf-8" }, }, },
          { timeout = { type = "number", default = 10000 }, },
          { keepalive = { type = "number", default = 60000 }, },
          { retry_count = { type = "integer" }, },
          { queue_size = { type = "integer" }, },
          { flush_timeout = { type = "number" }, },
          { headers = {
            type = "map",
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

        entity_checks = {
          { custom_entity_check = {
            field_sources = { "retry_count", "queue_size", "flush_timeout" },
            fn = function(entity)
              if entity.retry_count and entity.retry_count ~= 10 then
                deprecation("http-log: config.retry_count no longer works, please use config.queue.max_retry_time instead",
                            { after = "4.0", })
              end
              if entity.queue_size and entity.queue_size ~= 1 then
                deprecation("http-log: config.queue_size no longer works, please use config.queue.max_batch_size instead",
                            { after = "4.0", })
              end
              if entity.flush_timeout and entity.flush_timeout ~= 2 then
                deprecation("http-log: config.flush_timeout no longer works, please use config.queue.max_coalescing_delay instead",
                            { after = "4.0", })
              end
              return true
            end
          } },
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
