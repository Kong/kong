local IO = require "kong.tools.io"

local function validate_file(value)
  local exists = IO.file_exists(value)
  if not os.execute("touch "..value) == 0 then
    return false, "Cannot create a file in the path specified. Make sure the path is valid, and Kong has the right permissions"
  end

  if not exists then
    os.remove(value) -- Remove the created file if it didn't exist before
  end

  return true
end

return {
  fields = {
    path = { required = true, type = "string", func = validate_file }
  }
}
