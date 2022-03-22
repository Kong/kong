-- schema file for both the pre-function and post-function plugin
return function(plugin_name)

  local Schema = require "kong.db.schema"
  local typedefs = require "kong.db.schema.typedefs"

  local loadstring = loadstring


  local function validate_function(fun)
    local _, err = loadstring(fun)
    if err then
      return false, "error parsing " .. plugin_name .. ": " .. err
    end

    return true
  end


  local phase_functions = Schema.define {
    required = true,
    default = {},
    type = "array",
    elements = {
      type = "string",
      required = false,
      custom_validator = validate_function,
    }
  }

  return {
    name = plugin_name,
    fields = {
      { consumer = typedefs.no_consumer },
      {
        config = {
          type = "record",
          fields = {
            -- new interface
            { certificate = phase_functions },
            { rewrite = phase_functions },
            { access = phase_functions },
            { header_filter = phase_functions },
            { body_filter = phase_functions },
            { log = phase_functions },
          },
        },
      },
    },
    entity_checks = {
      { at_least_one_of = {
        "config.certificate",
        "config.rewrite",
        "config.access",
        "config.header_filter",
        "config.body_filter",
        "config.log",
      } },
    },
  }
end
