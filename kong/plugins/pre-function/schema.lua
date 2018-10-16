local typedefs = require "kong.db.schema.typedefs"


local function validate_function(fun)
  local _, err = loadstring(fun)
  if err then
    return false, "Error parsing pre-function: " .. err
  end

  return true
end


return {
  name = "pre-function",
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
