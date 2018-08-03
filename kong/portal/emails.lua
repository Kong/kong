local smtp_client = require "kong.enterprise_edition.smtp_client"
local fmt         = string.format
local log         = ngx.log
local INFO        = ngx.INFO


local _M = {}
local mt = { __index = _M }


_M.LOG_PREFIX = "[portal-smtp]"


local base_conf = {
  portal_invite_email = {
    name = "Invite",
    required_conf_keys = {
      "portal_emails_from",
      "portal_emails_reply_to",
      "portal_gui_url",
    },
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
    required_conf_keys = {
      "portal_emails_from",
      "portal_emails_reply_to",
      "portal_gui_url",
      "admin_gui_url",
      "smtp_admin_emails"
    },
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
    required_conf_keys = {
      "portal_emails_from",
      "portal_emails_reply_to",
      "portal_gui_url",
    },
    subject = "Developer Portal access approved (%s)",
    html = [[
      <p>Hello Developer!</p>
      <p>
        You have been approved to access %s.
        Please visit <a href="%s/login">%s/login</a> to login.
      </p>
    ]],
  },
}


function _M.new(conf)
  conf = conf or {}

  local enabled = conf.smtp

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
  })

  if err then
    log(INFO, _M.LOG_PREFIX, "unable to initialize smtp client: " .. err)
    enabled = false
  end

  local self = {
    enabled = enabled,
    client  = client,
    conf    = smtp_client.prep_conf(conf, base_conf),
  }

  return setmetatable(self, mt)
end


function _M:invite(recipients)
  if not self.enabled then
    return
  end

  local conf = self.conf.portal_invite_email
  local ok, err = self.client:check_conf(conf)
  if not ok then
    return nil, err
  end

  local options = {
    from = conf.portal_emails_from,
    reply_to = conf.portal_emails_reply_to,
    subject = fmt(conf.subject, conf.portal_gui_url),
    html = fmt(conf.html, conf.portal_gui_url, conf.portal_gui_url,
                                               conf.portal_gui_url),
  }

  local res
  -- send emails indiviually
  for _, recipient in ipairs(recipients) do
    res = self.client:send({recipient}, options, res)
  end

  return res
end


function _M:access_request(developer_email, developer_name)
  if not self.enabled then
    return
  end

  local conf = self.conf.portal_access_request_email
  local ok, err = self.client:check_conf(conf)
  if not ok then
    return nil, err
  end

  local options = {
    from = conf.portal_emails_from,
    reply_to = conf.portal_emails_reply_to,
    subject = fmt(conf.subject, conf.portal_gui_url),
    html = fmt(conf.html, developer_name, developer_email, conf.portal_gui_url,
                                  conf.admin_gui_url, conf.admin_gui_url),
  }

  return self.client:send(conf.smtp_admin_emails, options)
end


function _M:approved(recipient)
  if not self.enabled then
    return
  end

  local conf = self.conf.portal_approved_email
  local ok, err = self.client:check_conf(conf)
  if not ok then
    return nil, err
  end

  local options = {
    from = conf.portal_emails_from,
    reply_to = conf.portal_emails_reply_to,
    subject = fmt(conf.subject, conf.portal_gui_url),
    html = fmt(conf.html, conf.portal_gui_url, conf.portal_gui_url, conf.portal_gui_url),
  }

  return self.client:send({recipient}, options)
end


return _M
