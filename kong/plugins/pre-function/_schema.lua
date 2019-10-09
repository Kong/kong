-- schema file for both the pre-function and post-function plugin
return function(plugin_name)

  local typedefs = require "kong.db.schema.typedefs"
  local loadstring = loadstring


  local function validate_function(fun)
    local func1, err = loadstring(fun)
    if err then
      return false, "error parsing " .. plugin_name .. ": " .. err
    end

    return true
  end


  return {
    name = plugin_name,
    fields = {
      { consumer = typedefs.no_consumer },
      { config = {
          type = "record",
          fields = {
            { functions = {
                required = true, type = "array",
                elements = { type = "string", custom_validator = validate_function },
            }, },
          },
        },
      },
    },
  }

end
