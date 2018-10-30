local smtp_client  = require "kong.enterprise_edition.smtp_client"
local fmt          = string.format
local log          = ngx.log
local INFO         = ngx.INFO


local _M = {}
local mt = { __index = _M }


local _log_prefix = "[admin-smtp] "


local templates = {
  invite = {
    name = "Invite",
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
  }

  return setmetatable(self, mt)
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
  local registerUrl = (kong_conf.admin_gui_url or "")
                      .. "/register?email=" .. ngx.escape_uri(recipients[1])
                      .. "&token=" .. ngx.escape_uri(jwt)

  local options = {
    from = kong_conf.admin_emails_from,
    reply_to = kong_conf.admin_emails_reply_to,
    subject = fmt(template.subject),
    html = fmt(template.html,
               registerUrl,
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


return _M
