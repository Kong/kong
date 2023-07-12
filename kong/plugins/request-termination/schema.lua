local typedefs = require "kong.db.schema.typedefs"


local is_present = function(v)
  return type(v) == "string" and #v > 0
end


return {
  name = "request-termination",
  fields = {
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { status_code = { description = "The response code to send. Must be an integer between 100 and 599.", type = "integer",
            required = true,
            default = 503,
            between = { 100, 599 },
          }, },
          { message = { description = "The message to send, if using the default response generator.", type = "string" }, },
          { content_type = { description = "Content type of the raw response configured with `config.body`.", type = "string" }, },
          { body = { description = "The raw response body to send. This is mutually exclusive with the `config.message` field.", type = "string" }, },
          { echo = { description = "When set, the plugin will echo a copy of the request back to the client. The main usecase for this is debugging. It can be combined with `trigger` in order to debug requests on live systems without disturbing real traffic.", type = "boolean", required = true, default = false }, },
          { trigger = typedefs.header_name }
        },
        custom_validator = function(config)
          if is_present(config.message)
          and(is_present(config.content_type)
              or is_present(config.body)) then
            return nil, "message cannot be used with content_type or body"
          end
          if is_present(config.content_type)
          and not is_present(config.body) then
            return nil, "content_type requires a body"
          end
          if config.echo and (
            is_present(config.content_type) or
            is_present(config.body)) then
            return nil, "echo cannot be used with content_type and body"
          end
          return true
        end,
      },
    },
  },
}
