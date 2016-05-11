local pl_utils = require "pl.utils"

local function validate_file(value)
  local ok = pl_utils.executeex("touch "..value)
  if not ok then
    return false, "Cannot create file. Make sure the path is valid, and has the right permissions"
  end

  return true
end

return {
  fields = {
    path = { required = true, type = "string", func = validate_file }
  }
}
