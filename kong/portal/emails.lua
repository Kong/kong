local smtp_client  = require "kong.enterprise_edition.smtp_client"
local portal_utils = require "kong.portal.utils"
local singletons   = require "kong.singletons"
local ws_helper    = require "kong.workspaces.helper"
local constants    = require "kong.constants"

local ws_constants = constants.WORKSPACE_CONFIG
local fmt          = string.format
local log          = ngx.log
local INFO         = ngx.INFO


local _M = {}
local mt = { __index = _M }


_M.LOG_PREFIX = "[portal-smtp]"


local base_conf = {
  portal_invite_email = {
    name = "Invite",
    subject = "Invite to access Developer Portal (%s)",
    html = [[
      <p>Hello Developer!</p>
      <p>
        You have been invited to create a Developer Portal account at %s.
        Please visit <a href="%s/register">%s/register</a> to create your account.
      </p>
    ]],
  },

  portal_access_request_email = {
    name = "Access Request",
    subject = "Request to access Developer Portal (%s)",
    html = [[
      <p>Hello Admin!</p>
      <p>
        %s (%s) has requested Developer Portal access for %s.
        Please visit <a href="%s/developers/requested">%s/developers/requested</a> to review this request.
      </p>
    ]],
  },

  portal_approved_email = {
    name = "Approval",
    subject = "Developer Portal access approved (%s)",
    html = [[
      <p>Hello Developer!</p>
      <p>
        You have been approved to access %s.
        Please visit <a href="%s/login">%s/login</a> to login.
      </p>
    ]],
  },

  portal_reset_email = {
    name = "Password Reset",
    subject = "Password Reset Instructions for Developer Portal (%s)",
    html = [[
      <p>Hello Developer,</p>
      <p>
        Please click the link below to reset your Developer Portal password.
      </p>
      </p>
        <a href="%s/reset-password?token=%s">%s/reset?token=%s</a>
      </p>
      <p>
        This link will expire in %s.
      </p>
      <p>
      If you didn't make this request, keep your account secure by clicking the link above to change your password.
      </p>
    ]],
  },

  portal_reset_success_email = {
    name = "Password Reset Success",
    subject = "Developer Portal password change success (%s)",
    html = [[
      <p>Hello Developer,</p>
      <p>
        We are emailing you to let you know that your Developer Portal password at <a href="%s">%s</a> has been changed.
      </p>
      <p>
        Click the link below to sign in with your new credentials.
        <br>
        <a href="%s/login">%s/login</a>
      </p>
    ]],
  }
}


function _M:new()
  local client, err = smtp_client.new({
    host = singletons.configuration.smtp_host,
    port = singletons.configuration.smtp_port,
    starttls = singletons.configuration.smtp_starttls,
    ssl = singletons.configuration.smtp_ssl,
    username = singletons.configuration.smtp_username,
    password = singletons.configuration.smtp_password,
    auth_type = singletons.configuration.smtp_auth_type,
    domain = singletons.configuration.smtp_domain,
    timeout_connect = singletons.configuration.smtp_timeout_connect,
    timeout_send = singletons.configuration.smtp_timeout_send,
    timeout_read  = singletons.configuration.smtp_timeout_read,
  }, singletons.configuration.smtp_mock)

  if err then
    log(INFO, _M.LOG_PREFIX, "unable to initialize smtp client: " .. err)
  end

  local self = {
    client    = client,
    conf      = base_conf,
  }

  return setmetatable(self, mt)
end


function _M:invite(recipients)
  local workspace = ngx.ctx.workspaces and ngx.ctx.workspaces[1] or {}
  local portal_invite_email = ws_helper.retrieve_ws_config(ws_constants.PORTAL_INVITE_EMAIL, workspace)

  if not portal_invite_email then
    return nil, {code =  501, message = "portal_invite_email is disabled"}
  end

  local portal_emails_from = ws_helper.retrieve_ws_config(ws_constants.PORTAL_EMAILS_FROM, workspace)
  local portal_emails_reply_to = ws_helper.retrieve_ws_config(ws_constants.PORTAL_EMAILS_REPLY_TO, workspace)
  local conf = self.conf.portal_invite_email
  local options = {
    from = portal_emails_from,
    reply_to = portal_emails_reply_to,
    subject = fmt(conf.subject, singletons.configuration.portal_gui_url),
    html = fmt(conf.html, singletons.configuration.portal_gui_url, singletons.configuration.portal_gui_url,
                                                    singletons.configuration.portal_gui_url),
  }

  local res
  -- send emails indiviually
  for _, recipient in ipairs(recipients) do
    res = self.client:send({recipient}, options, res)
  end

  return smtp_client.handle_res(res)
end


function _M:access_request(developer_email, developer_name)
  local workspace = ngx.ctx.workspaces and ngx.ctx.workspaces[1] or {}
  local portal_access_request_email = ws_helper.retrieve_ws_config(ws_constants.PORTAL_ACCESS_REQUEST_EMAIL, workspace)

  if not portal_access_request_email then
    return nil
  end

  local portal_emails_from = ws_helper.retrieve_ws_config(ws_constants.PORTAL_EMAILS_FROM, workspace)
  local portal_emails_reply_to = ws_helper.retrieve_ws_config(ws_constants.PORTAL_EMAILS_REPLY_TO, workspace)
  local conf = self.conf.portal_access_request_email
  local options = {
    from = portal_emails_from,
    reply_to = portal_emails_reply_to,
    subject = fmt(conf.subject, singletons.configuration.portal_gui_url),
    html = fmt(conf.html, developer_name, developer_email,
                            singletons.configuration.portal_gui_url, singletons.configuration.admin_gui_url,
                                                      singletons.configuration.admin_gui_url),
  }

  local res = self.client:send(singletons.configuration.smtp_admin_emails, options)
  return smtp_client.handle_res(res)
end


function _M:approved(recipient)
  local workspace = ngx.ctx.workspaces and ngx.ctx.workspaces[1] or {}
  local portal_approved_email = ws_helper.retrieve_ws_config(ws_constants.PORTAL_APPROVED_EMAIL, workspace)

  if not portal_approved_email then
    return nil
  end

  local portal_emails_from = ws_helper.retrieve_ws_config(ws_constants.PORTAL_EMAILS_FROM, workspace)
  local portal_emails_reply_to = ws_helper.retrieve_ws_config(ws_constants.PORTAL_EMAILS_REPLY_TO, workspace)
  local conf = self.conf.portal_approved_email
  local options = {
    from = portal_emails_from,
    reply_to = portal_emails_reply_to,
    subject = fmt(conf.subject, singletons.configuration.portal_gui_url),
    html = fmt(conf.html, singletons.configuration.portal_gui_url, singletons.configuration.portal_gui_url,
                                                    singletons.configuration.portal_gui_url),
  }

  local res = self.client:send({recipient}, options)
  return smtp_client.handle_res(res)
end

function _M:password_reset(recipient, token)
  local workspace = ngx.ctx.workspaces and ngx.ctx.workspaces[1] or {}
  local portal_reset_email = ws_helper.retrieve_ws_config(ws_constants.PORTAL_RESET_EMAIL, workspace)

  if not portal_reset_email then
    return nil, {code =  501, message = "portal_reset_email is disabled"}
  end

  local exp_seconds = ws_helper.retrieve_ws_config(ws_constants.PORTAL_TOKEN_EXP, workspace)
  if not exp_seconds then
    return nil, {code =  500, message = "portal_token_exp is required"}
  end

  local portal_emails_from = ws_helper.retrieve_ws_config(ws_constants.PORTAL_EMAILS_FROM, workspace)
  local portal_emails_reply_to = ws_helper.retrieve_ws_config(ws_constants.PORTAL_EMAILS_REPLY_TO, workspace)
  local exp_string = portal_utils.humanize_timestamp(exp_seconds)
  local conf = self.conf.portal_reset_email
  local options = {
    from = portal_emails_from,
    reply_to = portal_emails_reply_to,
    subject = fmt(conf.subject, singletons.configuration.portal_gui_url),
    html = fmt(conf.html, singletons.configuration.portal_gui_url, token,
             singletons.configuration.portal_gui_url, token, exp_string),
  }

  local res = self.client:send({recipient}, options)
  return smtp_client.handle_res(res)
end

function _M:password_reset_success(recipient)
  local workspace = ngx.ctx.workspaces and ngx.ctx.workspaces[1] or {}
  local portal_reset_success_email = ws_helper.retrieve_ws_config(ws_constants.PORTAL_RESET_SUCCESS_EMAIL, workspace)

  if not portal_reset_success_email then
    return nil, {code =  501, message = "portal_reset_success_email is disabled"}
  end

  local portal_emails_from = ws_helper.retrieve_ws_config(ws_constants.PORTAL_EMAILS_FROM, workspace)
  local portal_emails_reply_to = ws_helper.retrieve_ws_config(ws_constants.PORTAL_EMAILS_REPLY_TO, workspace)
  local conf = self.conf.portal_reset_success_email
  local options = {
    from = portal_emails_from,
    reply_to = portal_emails_reply_to,
    subject = fmt(conf.subject, singletons.configuration.portal_gui_url),
    html = fmt(conf.html, singletons.configuration.portal_gui_url, singletons.configuration.portal_gui_url,
                          singletons.configuration.portal_gui_url, singletons.configuration.portal_gui_url),
  }

  local res = self.client:send({recipient}, options)
  return smtp_client.handle_res(res)
end

return _M
