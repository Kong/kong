local smtp_client  = require "kong.enterprise_edition.smtp_client"
local portal_utils = require "kong.portal.utils"
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


function _M.new(conf)
  conf = conf or {}

  local client, err = smtp_client.new({
    host = conf.portal_smtp_host,                  -- default localhost
    port = conf.portal_smtp_port,                  -- default 25
    starttls = conf.portal_smtp_starttls,          -- default nil
    ssl = conf.portal_smtp_ssl,                    -- default nil
    username = conf.portal_smtp_username,          -- default nil
    password = conf.portal_smtp_password,          -- default nil
    auth_type = conf.portal_smtp_auth_type,        -- default nil
    domain = conf.portal_smtp_domain,              -- default localhost.localdomain
    timeout_connect = conf.portal_smtp_timeout_connect, -- default 60000 (ms)
    timeout_send = conf.portal_smtp_timeout_send,  -- default 60000 (ms)
    timeout_read  = conf.portal_smtp_timeout_read, -- default 60000 (ms)
  }, conf.smtp_mock)

  if err then
    log(INFO, _M.LOG_PREFIX, "unable to initialize smtp client: " .. err)
  end

  local self = {
    client    = client,
    conf      = base_conf,
    kong_conf = conf,
  }

  return setmetatable(self, mt)
end


function _M:invite(recipients)
  local kong_conf = self.kong_conf
  if not kong_conf.portal_invite_email then
    return nil, {code =  501, message = "portal_invite_email is disabled"}
  end

  local conf = self.conf.portal_invite_email
  local options = {
    from = kong_conf.portal_emails_from,
    reply_to = kong_conf.portal_emails_reply_to,
    subject = fmt(conf.subject, kong_conf.portal_gui_url),
    html = fmt(conf.html, kong_conf.portal_gui_url, kong_conf.portal_gui_url,
                                                    kong_conf.portal_gui_url),
  }

  local res
  -- send emails indiviually
  for _, recipient in ipairs(recipients) do
    res = self.client:send({recipient}, options, res)
  end

  return smtp_client.handle_res(res)
end


function _M:access_request(developer_email, developer_name)
  local kong_conf = self.kong_conf
  if not kong_conf.portal_access_request_email then
    return nil
  end

  local conf = self.conf.portal_access_request_email
  local options = {
    from = kong_conf.portal_emails_from,
    reply_to = kong_conf.portal_emails_reply_to,
    subject = fmt(conf.subject, kong_conf.portal_gui_url),
    html = fmt(conf.html, developer_name, developer_email,
                            kong_conf.portal_gui_url, kong_conf.admin_gui_url,
                                                      kong_conf.admin_gui_url),
  }

  local res = self.client:send(kong_conf.smtp_admin_emails, options)
  return smtp_client.handle_res(res)
end


function _M:approved(recipient)
  local kong_conf = self.kong_conf
  if not kong_conf.portal_approved_email then
    return nil
  end

  local conf = self.conf.portal_approved_email
  local options = {
    from = kong_conf.portal_emails_from,
    reply_to = kong_conf.portal_emails_reply_to,
    subject = fmt(conf.subject, kong_conf.portal_gui_url),
    html = fmt(conf.html, kong_conf.portal_gui_url, kong_conf.portal_gui_url,
                                                    kong_conf.portal_gui_url),
  }

  local res = self.client:send({recipient}, options)
  return smtp_client.handle_res(res)
end

function _M:password_reset(recipient, token)
  local kong_conf = self.kong_conf
  if not kong_conf.portal_reset_email then
    return nil, {code =  501, message = "portal_reset_email is disabled"}
  end

  local exp_seconds = kong_conf.portal_token_exp
  if not exp_seconds then
    return nil, {code =  500, message = "portal_token_exp is required"}
  end

  local exp_string = portal_utils.humanize_timestamp(exp_seconds)
  local conf = self.conf.portal_reset_email
  local options = {
    from = kong_conf.portal_emails_from,
    reply_to = kong_conf.portal_emails_reply_to,
    subject = fmt(conf.subject, kong_conf.portal_gui_url),
    html = fmt(conf.html, kong_conf.portal_gui_url, token,
             kong_conf.portal_gui_url, token, exp_string),
  }

  local res = self.client:send({recipient}, options)
  return smtp_client.handle_res(res)
end

function _M:password_reset_success(recipient)
  local kong_conf = self.kong_conf
  if not kong_conf.portal_reset_success_email then
    return nil, {code =  501, message = "portal_reset_success_email is disabled"}
  end

  local conf = self.conf.portal_reset_success_email
  local options = {
    from = kong_conf.portal_emails_from,
    reply_to = kong_conf.portal_emails_reply_to,
    subject = fmt(conf.subject, kong_conf.portal_gui_url),
    html = fmt(conf.html, kong_conf.portal_gui_url, kong_conf.portal_gui_url,
                          kong_conf.portal_gui_url, kong_conf.portal_gui_url),
  }

  local res = self.client:send({recipient}, options)
  return smtp_client.handle_res(res)
end

return _M
