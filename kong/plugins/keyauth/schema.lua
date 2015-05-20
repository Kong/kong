local utils = require "kong.tools.utils"

local function default_key_names(t)
  if not t.key_names then
    return {"apikey"}
  end
end

local function validate_key_names(t)
  if type(t) == "table" and not utils.is_array(t) then
    local printable_mt = require "kong.tools.printable"
    setmetatable(t, printable_mt)
    return false, "key_names must be an array. '"..t.."' is a table. Lua tables must have integer indexes starting at 1."
  end

  return true
end

return {
  key_names = { required = true, type = "table", default = default_key_names, func = validate_key_names },
  hide_credentials = { type = "boolean", default = false }
}
