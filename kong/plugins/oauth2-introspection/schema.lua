local utils = require "kong.tools.utils"

local function check_user(anonymous)
  if anonymous == "" or utils.is_valid_uuid(anonymous) then
    return true
  end

  return false, "the anonymous user must be empty or a valid uuid"
end

return {
  no_consumer = true,
  fields = {
    introspection_url = {type = "url", required = true},
    ttl = {type = "number", default = 30},
    token_type_hint = {type = "string"},
    authorization_value = {type = "string", required = true},
    timeout = {default = 10000, type = "number"},
    keepalive = {default = 60000, type = "number"},
    hide_credentials = { type = "boolean", default = false },
    run_on_preflight = {type = "boolean", default = true},
    anonymous = {type = "string", default = "", func = check_user},
  }
}
