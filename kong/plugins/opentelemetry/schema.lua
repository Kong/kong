local typedefs = require "kong.db.schema.typedefs"
local Schema = require "kong.db.schema"
local deprecation = require("kong.deprecation")

local function custom_validator(attributes)
  for _, v in pairs(attributes) do
    local vtype = type(v)
    if vtype ~= "string" and
       vtype ~= "number" and
       vtype ~= "boolean"
    then
      return nil, "invalid type of value: " .. vtype
    end

    if vtype == "string" and #v == 0 then
      return nil, "required field missing"
    end
  end

  return true
end

local resource_attributes = Schema.define {
  type = "map",
  keys = { type = "string", required = true },
  -- TODO: support [string, number, boolean]
  values = { type = "string", required = true },
  custom_validator = custom_validator,
}

return {
  name = "opentelemetry",
  fields = {
    { protocols = typedefs.protocols_http }, -- TODO: support stream mode
    { config = {
      type = "record",
      fields = {
        { endpoint = typedefs.url { required = true } }, -- OTLP/HTTP
        { headers = {
          type = "map",
          keys = typedefs.header_name,
          values = {
            type = "string",
            referenceable = true,
          },
        } },
        { resource_attributes = resource_attributes },
        { queue = typedefs.queue },
        { connect_timeout = typedefs.timeout { default = 1000 } },
        { send_timeout = typedefs.timeout { default = 5000 } },
        { read_timeout = typedefs.timeout { default = 5000 } },
      },
      entity_checks = {
        { custom_entity_check = {
          field_sources = { "batch_span_count", "batch_flush_delay" },
          fn = function(entity)
            if entity.batch_span_count then
              deprecation("batch_span_count is deprecated, please use queue.batch_max_size instead",
                          { after = "4.0", })
            end
            if entity.batch_flush_delay then
              deprecation("batch_flush_delay is deprecated, please use queue.batch_max_size instead",
                          { after = "4.0", })
            end
            return true
          end
        } },
      },
      shorthand_fields = {
        { batch_span_count = { type = "integer", required = true, default = 200, func = function(value)
            return { ["queue.batch_max_size"] = value }
          end,
        }, },
        { batch_flush_delay = { type = "integer", required = true, default = 3, func = function(value)
            return { ["queue.max_delay"] = value }
          end,
        }, },
      },
    } },
  },
}
