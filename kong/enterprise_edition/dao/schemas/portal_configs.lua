local portal_utils = require "kong.portal.utils"
 

local function check_portal_auth(auth)
  if auth ~= nil
    and auth ~= "basic-auth"
    and auth ~= "key-auth"
    and auth ~= "openid-connect" then
    return false, "invalid auth type"
  end

  return true
end


local function check_portal_token_exp (timeout)
  if timeout ~= nil and timeout < 0 then
    return false, "`portal_token_exp` must be more than 0"
  end

  return true
end


local function validate_email(email)
  if email ~= nil then
    local ok, err = portal_utils.validate_email(email)
    if not ok then
      return false, email .. " is invalid: " .. err
    end
  end

  return true
end


return {
  table = "portal_configs",
  primary_key = { "id" },
  workspaceable = true,
  fields = {
    id = {
      type = "id",
      dao_insert_value = true,
      required = true,
    },
    portal_auth = {
      type = "string",
      func = check_portal_auth,
    },
    portal_auth_config = {
      type = "string",
    },
    portal_auto_approve = {
      type = "boolean",
    },
    portal_token_exp = {
      type = "number",
      func = check_portal_token_exp,
    },
    portal_invite_email = {
      type = "boolean",
    },
    portal_access_request_email = {
      type = "boolean",
    },
    portal_approved_email = {
      type = "boolean",
    },
    portal_reset_email = {
      type = "boolean",
    },
    portal_reset_success_email = {
      type = "boolean",
    },
    portal_emails_from = {
      type = "string",
      func = validate_email,
    },
    portal_emails_reply_to = {
      type = "string",
      func = validate_email,
    },
  },
}
