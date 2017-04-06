local pl_file = require "pl.file"
local pl_path = require "pl.path"

local function validate_file(value)
  -- create file in case it doesn't exist
  if not pl_path.exists(value) then
    local ok, err = pl_file.write(value, "")
    if not ok then return false, string.format("Cannot create file: %s", err) end
  end

  return true
end

return {
  fields = {
    path = { required = true, type = "string", func = validate_file },
    reopen = { type = "boolean", default = false },
  }
}
