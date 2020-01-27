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
          { status_code = {
            type = "integer",
            default = 503,
            between = { 100, 599 },
          }, },
          { message = { type = "string" }, },
          { content_type = { type = "string" }, },
          { body = { type = "string" }, },
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
          return true
        end,
      },
    },
  },
}
