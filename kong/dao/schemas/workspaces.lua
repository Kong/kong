local portal_utils = require "kong.portal.utils"
local workspaces   = require "kong.workspaces"


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
    return false, "`portal_token_exp` must be equal to or greater than 0"
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


local function config_schema(workspace_t)
  return {
    fields = {
      portal = {
        type = "boolean",
        required = true,
        default = workspace_t.name == workspaces.DEFAULT_WORKSPACE,
      },
      portal_auth = {
        type = "string",
        func = check_portal_auth,
      },
      portal_auth_conf = {
        type = "table",
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
end


local function check_name(name)
  if name then
    local m, err = ngx.re.match(name, "[^\\w.\\-_~]")
    if err then
      ngx.log(ngx.ERR, err)
      return

    elseif m then
      return false, "name must only contain alphanumeric and '., -, _, ~' characters"
    end
  end

  return true
end


return {
  table = "workspaces",
  primary_key = { "id" },
  cache_key = { "name" },
  fields = {
    id = {
      type = "id",
      dao_insert_value = true,
      required = true,
    },
    name = {
      type = "string",
      required = true,
      unique = true,
      func = check_name
    },
    comment = {
      type = "string",
    },
    created_at = {
      type = "timestamp",
      immutable = true,
      dao_insert_value = true,
      required = true,
    },
    meta = {
      type = "table",
      default = {},
    },
    config = {
      type = "table",
      default = {},
      schema = config_schema,
      required = true,
    },
  },
}
