local utils = require "kong.tools.utils"

local function default_key_names(t)
  if not t.key_names then
    return {"apikey"}
  end
end

return {
  key_names = { required = true, type = "array", default = default_key_names },
  hide_credentials = { type = "boolean", default = false }
}
