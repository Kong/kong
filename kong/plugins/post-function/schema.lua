local Errors = require "kong.dao.errors"


local function check_functions(value)
  for i, entry in ipairs(value) do
    local _, err = loadstring(entry)
    if err then
      return false, Errors.schema("Error parsing post-function #" .. i .. ": " .. err)
    end
  end

  return true
end


return {
  no_consumer = true,
  api_only = true,

  fields = {
    functions = {
      required = true,
      type = "array",
    }
  },

  self_check = function(schema, config, dao, is_updating)
    local _, err = check_functions(config.functions)
    if err then
      return false, err
    end

    return true
  end,
}
