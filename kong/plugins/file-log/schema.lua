local pl_file = require "pl.file"
local pl_path = require "pl.path"
local typedefs = require "kong.db.schema.typedefs"

local function validate_file(value)
  -- create file in case it doesn't exist
  if not pl_path.exists(value) then
    local ok, err = pl_file.write(value, "")
    if not ok then
      return nil, string.format("Cannot create file: %s", err)
    end
  end

  return true
end

return {
  name = "file-log",
  fields = {
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { path = { type = "string",
                     required = true,
                     custom_validator = validate_file,
          }, },
          { reopen = { type = "boolean", default = false }, },
          { serializer = { type = "foreign", reference = "log_serializers" } },
    }, }, },
  }
}
