-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local lpeg     = require "lpeg"
local Schema   = require "kong.db.schema"
local lp_email = require "lpeg_patterns.email"
local typedefs = require "kong.db.schema.typedefs"
local constants = require "kong.constants"

local is_regex = Schema.validators.is_regex
local EOF = lpeg.P(-1)
local email_validator_pattern = lp_email.email_nocfws * EOF


local function validate_email(str)
  local has_match = email_validator_pattern:match(str)
  if not has_match then
    return nil, "invalid email address " .. str
  end
  return true
end


local function validate_portal_auth(portal_auth)
  return portal_auth == "openid-connect" or
         portal_auth == "basic-auth" or
         portal_auth == "key-auth" or
         portal_auth == "" or
         portal_auth == nil
end


local function validate_asterisk_or_regex(value)
  if value == "*" or is_regex(value) then
    return true
  end

  return nil, string.format("'%s' is not a valid regex", tostring(value))
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
    { portal_application_status_email = { type = "boolean" } },
    { portal_application_request_email = { type = "boolean" } },
    { portal_emails_from = { type = "string", custom_validator = validate_email } },
    { portal_emails_reply_to = { type = "string", custom_validator = validate_email } },
    { portal_smtp_admin_emails = { type = "array", elements = { type = "string", custom_validator = validate_email } } },
    { portal_cors_origins = { type = "array", elements = { type = "string", custom_validator = validate_asterisk_or_regex } } },
    { portal_developer_meta_fields = { type  = "string" , default =
      "[{\"label\":\"Full Name\",\"title\":\"full_name\",\"validator\":{\"required\":true,\"type\":\"string\"}}]"} },
    { portal_session_conf = { type = "string" } },
    { portal_is_legacy = { type = "boolean" } },
  }
}

local function validate_color_hex(value)
  if value:match('^#%w%w%w%w%w%w$') then
    return true
  end

  return nil, string.format("'%s' is not a valid color", tostring(value))
end

local function validate_image(value)
  if value:match('^data:image/[a-zA-Z]+;base64,[a-zA-Z0-9/+]+=*$') then
    return true
  end

  return nil, string.format("thumbnail is not a valid image data uri", tostring(value))
end


-- XXX by attempting to make the `meta` field a map, I found a bug in
-- Kong's cassandra query serializer (where it'd attempt to index an
-- `elements` field in the map schema, whereas it contains keys and values,
-- not elements
local config_meta = {
  type = "record",
  fields = {
    { color = { type = "string", custom_validator = validate_color_hex } },
    { thumbnail = { type = "string", custom_validator = validate_image } },
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
    { name        = typedefs.utf8_name { required = true, not_one_of = { table.unpack(constants.CORE_ENTITIES) }, indexed = true, } },
    { comment     = { description = "A description or additional information about the workspace.", type = "string" } },
    { created_at  = typedefs.auto_timestamp_s },
    { updated_at  = typedefs.auto_timestamp_s },
    { meta        = config_meta },
    { config      = config_schema },
  }
}
