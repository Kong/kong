local lpeg     = require "lpeg"
local Schema   = require "kong.db.schema"
local lp_email = require "lpeg_patterns.email"
local typedefs = require "kong.db.schema.typedefs"

local EOF = lpeg.P(-1)
local email_validator_pattern = lp_email.email_nocfws * EOF


local email = Schema.define {
  type = "string",
  custom_validator = function(s)
    local has_match = email_validator_pattern:match(s)
    if not has_match then
      return nil, "invalid email address " .. s
    end
    return true
  end
}


local function validate_portal_auth(portal_auth)
  return portal_auth == "openid-connect" or
         portal_auth == "basic-auth" or
         portal_auth == "key-auth" or
         portal_auth == "" or
         portal_auth == nil
end


local config_schema = {
  type = "record",

  fields = {
    { portal = { type = "boolean", required = true, default = false } },
    -- XXX supported auth should not be hardcoded here, but instead set in a single place,
    -- in the portal module
    { portal_auth = { type = "string", len_min = 0, custom_validator = validate_portal_auth } },
    { portal_auth_conf = { type = "string" } },
    { meta = { type = "map", keys = { type = "string" }, values = { type = "string" } } },
    { portal_auto_approve = { type = "boolean" } },
    -- XXX gt -1 will not read as natural/friendly as ge (>=) 0 - but there's no ge
    { portal_token_exp = { type = "integer", gt = -1 } },
    { portal_invite_email = { type = "boolean" } },
    { portal_access_request_email = { type = "boolean" } },
    { portal_approved_email = { type = "boolean" } },
    { portal_reset_email = { type = "boolean" } },
    { portal_reset_success_email = { type = "boolean" } },
    { portal_emails_from = email },
    { portal_emails_reply_to = email },
    { portal_cors_origins = { type = "array", elements = { type = "string", is_regex = true } } },
    { portal_developer_meta_fields = { type  = "string" , default =
      "[{\"label\":\"Full Name\",\"title\":\"full_name\",\"validator\":{\"required\":true,\"type\":\"string\"}}]"} },
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
    { thumbnail = { type = "string" } },
  }
}


return {
  name = "workspaces",
  primary_key = { "id" },
  cache_key = { "name" },
  endpoint_key = "name",
  dao          = "kong.db.dao.workspaces",

  fields = {
    { id          = typedefs.uuid },
    { name        = typedefs.name { required = true } },
    { comment     = { type = "string" } },
    { created_at  = typedefs.auto_timestamp_s },
    { meta        = config_meta },
    { config      = config_schema },
  }
}
