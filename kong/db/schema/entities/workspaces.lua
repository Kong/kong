local enterprise_utils = require "kong.enterprise_edition.utils"
local typedefs = require "kong.db.schema.typedefs"


local function validate_email(email)
  if email ~= nil then
    local ok, err = enterprise_utils.validate_email(email)
    if not ok then
      return false, email .. " is invalid: " .. err
    end
  end

  return true
end


local config_schema = {
  type = "record",

  fields = {
    -- XXX revisit the default (needs to be true iff workspace == default)
    { portal = { type = "boolean", required = true, default = false } },
    -- XXX supported auth should not be hardcoded here, but instead set in a single place,
    -- in the portal module
    { portal_auth = { type = "string", one_of = {"basic-auth", "key-auth", "openid-connect"} } },
    { meta = { type = "map", keys = { type = "string" }, values = { type = "string" } } },
    { portal_auto_approve = { type = "boolean" } },
    -- XXX gt -1 will not read as natural/friendly as ge (>=) 0 - but there's no ge
    { portal_token_exp = { type = "integer", gt = -1 } },
    { portal_invite_email = { type = "boolean" } },
    { portal_access_request_email = { type = "boolean" } },
    { portal_approved_email = { type = "boolean" } },
    { portal_reset_email = { type = "boolean" } },
    { portal_reset_success_email = { type = "boolean" } },
    { portal_emails_from = { type = "string", custom_validator = validate_email} },
    { portal_emails_reply_to = { type = "string", custom_validator = validate_email } },
    { portal_cors_origins = { type = "array", elements = { type = "string", is_regex = true } } },
  }
}


-- XXX by attempting to make the `meta` field a map, I found a bug in
-- Kong's cassandra query serializer (where it'd attempt to index an
-- `elements` field in the map schema, whereas it contains keys and values,
-- not elements
local config_meta = {
  type = "record",
  fields = {
    -- XXX add a validator for this field (perhaps `matches` with a Lua
    -- pattern for the color hex code?
    { color = { type = "string" } },
  }
}


return {
  name = "workspaces",
  primary_key = { "id" },
  cache_key = { "name" },
  endpoint_key = "name",

  fields = {
    { id          = typedefs.uuid },
    { name        = typedefs.name { required = true } },
    { comment     = { type = "string" } },
    { created_at  = typedefs.auto_timestamp_s },
    { meta        = config_meta },
    { config      = config_schema },
  }
}
