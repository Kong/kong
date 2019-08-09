local typedefs = require "kong.db.schema.typedefs"
local file_helpers = require "kong.portal.file_helpers"

local match = string.match

local function validate_path(path)
  if path:sub(1, 1) == "/" then
    return nil, "path must not begin with a slash '/'"
  end

  local ext = match(path, "%.(%w+)$")
  if not ext then
    return false, "path must end with a file extension"
  end

  if file_helpers.is_content_path(path) then
    local ok, err = file_helpers.is_valid_content_ext(path)
    if not ok then
      return nil, err
    end

  elseif not file_helpers.is_html_ext(path) and
         file_helpers.is_layout_path(path) or
         file_helpers.is_partial_path(path) then
      return nil, "layouts and partials must end with extension '.html'"
  end

  return true
end

return {
  name = "files",
  primary_key = { "id" },
  workspaceable = true,
  endpoint_key  = "path",
  dao           = "kong.db.dao.files",

  fields = {
    { id         = typedefs.uuid, },
    { created_at = typedefs.auto_timestamp_s },
    { path       = { type = "string",
                     required = true,
                     unique = true,
                     custom_validator = validate_path } },
    { contents   = { type = "string", len_min = 0, required = true } },
    { checksum   = { type = "string", len_min = 0 } },
  },
}
