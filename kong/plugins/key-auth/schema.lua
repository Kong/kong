local utils = require "kong.tools.utils"


local function check_user(anonymous)
  if anonymous == "" or utils.is_valid_uuid(anonymous) then
    return true
  end

  return false, "the anonymous user must be empty or a valid uuid"
end


local function check_keys(keys)
  for _, key in ipairs(keys) do
    local res, err = utils.validate_header_name(key, false)

    if not res then
      return false, "'" .. key .. "' is illegal: " .. err
    end
  end

  return true
end


local function check_key(key)
  local res, err = utils.validate_header_name(key, false)

  if not res then
    return false, "'" .. key .. "' is illegal: " .. err
  end
  return true
end


return {
  no_consumer = true,
  fields = {
    key_names = {
      new_type = {
        type = "array",
        required = true,
        elements = {
          type = "string",
          custom_validator = check_key,
        },
        nullable = false,
        default = { "apikey" },
      },
      required = true,
      type = "array",
      default = { "apikey" },
      func = check_keys,
    },
    hide_credentials = {
      type = "boolean",
      default = false,
    },
    anonymous = {
      type = "string",
      default = "",
      func = check_user,
    },
    key_in_body = {
      type = "boolean",
      default = false,
    },
    run_on_preflight = {
      type = "boolean",
      default = true,
    },
  }
}
