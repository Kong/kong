local typedefs = require "kong.db.schema.typedefs"
local utils = require "kong.tools.utils"


local function check_user(anonymous)
  if anonymous == "" or utils.is_valid_uuid(anonymous) then
    return true
  end

  return false, "the anonymous user must be empty or a valid uuid"
end


return {
  name = "oauth2-introspection",
  fields = {
    { consumer = typedefs.no_consumer },
    { config = {
      type = "record",
      fields = {
        { introspection_url = typedefs.url { required = true} },
        { ttl = { type = "number", default = 30 } },
        { token_type_hint = { type = "string" } },
        { authorization_value = { type = "string", required = true } },
        { timeout = { type = "integer", default = 10000 } },
        { keepalive = { type = "integer", default = 60000 } },
        { hide_credentials = { type = "boolean", default = false } },
        { run_on_preflight = {type = "boolean", default = true} },
        { anonymous = {type = "string", len_min = 0, default = "", custom_validator = check_user } },
      }}
    },
  },
}
