local smtp_client  = require "kong.enterprise_edition.smtp_client"
local fmt          = string.format
local log          = ngx.log
local INFO         = ngx.INFO


local _M = {}
local mt = { __index = _M }


local _log_prefix = "[admin-smtp] "


local templates = {
  invite = {
    subject = "You're invited to Kong Manager",
    html = [[
      <p>
      You're receiving this email because your Kong administrator has added you
      as a user of Kong Manager.
      </p>
      <p>
      Kong Manager simplifies API management by allowing you to configure your
      services and view performance metrics of your Kong cluster.
      </p>
      <p>
      Click the following link to <a href="%s">register</a>.
      </p>
      <p>
      This link expires in %s hours.
      </p>
      <p>
      For more information about what you can do with Kong Manager,
      check out our <a href="%s">docs</a>.
      </p>
    ]],
  },
  password_reset = {
    subject = "Password Reset Instructions for Kong Manager",
    html = [[
      <p>Hello,</p>
      <p>
        Please click the link below to reset your Kong Manager password.
      </p>
      </p>
        <a href="%s">%s</a>
      </p>
      <p>
        This link expires in %s hours.
      </p>
      <p>
      If you didn't make this request, keep your account secure by clicking the
      link above to change your password.
      </p>
    ]]
  },
  password_reset_success = {
    subject = "Your Kong Manager Password has Changed",
    html = [[
      <p>Hello,</p>
      <p>
        We are emailing you to let you know that your Kong Manager password
        has been changed.
      </p>
      <p>
        Click the link below to sign in with your new credentials.
      </p>
      <p>
        <a href="%s">%s</a>
      </p>
    ]],
  }
}

function _M.new(conf)
  conf = conf or {}
  local client, err = smtp_client.new_smtp_client(conf)
  if err then
    log(INFO, _log_prefix, "unable to initialize smtp client: ", err)
  end

  local self = {
    client    = client,
    templates = templates,
    kong_conf = conf,
    admin_gui_url = conf.admin_gui_url or "",
  }

  return setmetatable(self, mt)
end

function _M:register_url(email, jwt)
  return fmt("%s/register?email=%s&token=%s",
    self.admin_gui_url, ngx.escape_uri(email), ngx.escape_uri(jwt))
end

function _M:invite(recipients, jwt)
  if not next(recipients) then
    return nil, {code = 500, message = "recipients required"}
  end
  local kong_conf = self.kong_conf
  if not kong_conf.admin_invite_email then
    return nil, {code = 501, message = "admin_invite_email is disabled"}
  end

  local template = self.templates.invite
  
  local options = {
    from = kong_conf.admin_emails_from,
    reply_to = kong_conf.admin_emails_reply_to,
    subject = fmt(template.subject),
    html = fmt(template.html,
               self:register_url(recipients[1], jwt),
               kong_conf.admin_invitation_expiry / 60 / 60,
               kong_conf.admin_docs_url),
  }

  local res
  -- send emails individually
  for _, recipient in ipairs(recipients) do
    res = self.client:send({recipient}, options, res)
  end

  return smtp_client.handle_res(res)
end


function _M:reset_password(email, jwt)
  if not email then
    return nil, { code = 500, message = "email required" }
  end

  local template = self.templates.password_reset
  local reset_url = (self.kong_conf.admin_gui_url or "") ..
                    "/account/reset-password?email=" .. ngx.escape_uri(email) ..
                    "&token=" .. ngx.escape_uri(jwt)

  local options = {
    from = self.kong_conf.admin_emails_from,
    reply_to = self.kong_conf.admin_emails_reply_to,
    subject = fmt(template.subject),
    html = fmt(template.html,
      reset_url, reset_url,
      self.kong_conf.admin_invitation_expiry / 60 / 60),
  }

  local res = self.client:send({ email }, options)

  return smtp_client.handle_res(res)
end


function _M:reset_password_success(email)
  if not email then
    return nil, { code = 500, message = "email required" }
  end

  local template = self.templates.password_reset_success
  local login_url = (self.kong_conf.admin_gui_url or "") .. "/login"

  local options = {
    from = self.kong_conf.admin_emails_from,
    reply_to = self.kong_conf.admin_emails_reply_to,
    subject = fmt(template.subject),
    html = fmt(template.html, login_url, login_url),
  }

  local res = self.client:send({ email }, options)

  return smtp_client.handle_res(res)
end


return _M
