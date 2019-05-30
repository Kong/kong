-- schema file for both the pre-function and post-function plugin
return function(plugin_name)

  local typedefs = require "kong.db.schema.typedefs"


  local function validate_function(fun)
    local func1, err = loadstring(fun)
    if err then
      return false, "Error parsing " .. plugin_name .. ": " .. err
    end

    local success, func2 = pcall(func1)

    if not success or func2 == nil then
      -- the code IS the handler function
      return true
    end

    -- the code RETURNED the handler function
    if type(func2) == "function" then
      return true
    end

    -- the code returned something unknown
    return false, "Bad return value from " .. plugin_name .. " function, " ..
                  "expected function type, got " .. type(func2)
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
