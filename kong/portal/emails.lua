-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local smtp_client  = require "kong.enterprise_edition.smtp_client"
local portal_utils = require "kong.portal.utils"
local workspaces = require "kong.workspaces"
local workspace_config = require "kong.portal.workspace_config"
local constants    = require "kong.constants"
local cjson        = require "cjson.safe"

local ws_constants = constants.WORKSPACE_CONFIG
local fmt          = string.format
local log          = ngx.log
local INFO         = ngx.INFO
local PORTAL_DEVELOPER_META_FIELDS = ws_constants.PORTAL_DEVELOPER_META_FIELDS

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
      <p>
        <a href="%s/reset-password?token=%s">%s/reset-password?token=%s</a>
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
  },

  portal_account_verification_email = {
    name = "Developer Portal Account Verification",
    subject = "Developer Portal Account Verification (%s)",
    html = [[
      <p>Hello Developer!</p>
      <p>
        Please click the link below to verify your Developer Portal account at %s.
      </p>
      <p>
        <a href="%s/account/verify?token=%s&email=%s">verify account</a>
      </p>
      <p>
        If you didn't make this request, please click the link below to invalidate this request.
      </p>
      <p>
        <a href="%s/account/invalidate-verification?token=%s&email=%s">invalidate validation request</a>
      </p>
    ]],
  },

  portal_account_verification_success_approved_email = {
    name = "Developer Portal Account Verification Success",
    subject = "Developer Portal account verification success (%s)",
    html = [[
      <p>Hello Developer,</p>
      <p>
        We are emailing you to let you know that your Developer Portal account at <a href="%s">%s</a> has been verified.
      </p>
      <p>
        Click the link below to Sign in.
        <br>
        <a href="%s/login">%s/login</a>
      </p>
    ]],
  },

  portal_account_verification_success_pending_email = {
    name = "Developer Portal Account Verification Success",
    subject = "Developer Portal account verification success (%s)",
    html = [[
      <p>Hello Developer,</p>
      <p>
        We are emailing you to let you know that your Developer Portal account at <a href="%s">%s</a> has been verified.
      </p>
      <p>
        Your account is still pending approval.  You will receive another email when your account has been approved.
      </p>
    ]],
  },

  portal_application_service_approved_email = {
    name = "Developer Portal Application Request Approved",
    subject = "Developer Portal application request approved (%s)",
    html = [[
      <p>Hello Developer,</p>
      <p>
        We are emailing you to let you know that your request for application access from the
        Developer Portal account at <a href="%s">%s</a> has been approved.
      </>
      <p>
        Application: %s
      </p>
    ]]
  },

  portal_application_service_rejected_email = {
    name = "Developer Portal Application Request Denied",
    subject = "Developer Portal application request denied (%s)",
    html = [[
      <p>Hello Developer,</p>
      <p>
        We are emailing you to let you know that your request for application access from the
        Developer Portal account at <a href="%s">%s</a> has been denied.
      </>
      <br>
      <p>
        Application: %s
      </p>
    ]]
  },

  portal_application_service_revoked_email = {
    name = "Developer Portal Application Request Revoked",
    subject = "Developer Portal application request revoked (%s)",
    html = [[
      <p>Hello Developer,</p>
      <p>
        We are emailing you to let you know that your request for application access from the
        Developer Portal account at <a href="%s">%s</a> has been revoked.
      </>
      <br>
      <p>
        Application: %s
      </p>
    ]]
  },

  portal_application_service_pending_email = {
    name = "Developer Portal Application Request Pending",
    subject = "Developer Portal application request pending (%s)",
    html = [[
      <p>Hello Developer,</p>
      <p>
        We are emailing you to let you know that your request for application access from the
        Developer Portal account at <a href="%s">%s</a> is pending.
      </>
      <p>
        Application: %s
      </p>
      <p>
        You will receive another email when your access has been approved.
      </p>
    ]]
  },

  portal_application_service_requested_email = {
    name = "Developer Portal Application Requested",
    subject = "Request to access Developer Portal (%s) service from %s",
    html = [[
      <p>Hello Admin,</p>
      <p>
        %s (%s) has requested application access for %s.
      </>
      <p>
        Requested workspace: %s
        <br>
        Requested application: %s
      </p>
      <p>
        Please visit <a href="%s/applications/%s#requested">
          %s/applications/%s#requested
        </a> to review this request.
      </p>
    ]]
  },
}

local function get_admin_emails(workspace)
  -- Use `portal_smtp_admin_emails` if available
  local admin_emails = workspace_config.retrieve(ws_constants.PORTAL_SMTP_ADMIN_EMAILS, workspace)

  -- Fallback to `smtp_admin_emails`
  if type(admin_emails) ~= "table" or next(admin_emails) == nil then
    admin_emails = kong.configuration.smtp_admin_emails
  end

  return admin_emails
end


function _M:get_example_email_tokens(path)
  local workspace = workspaces.get_workspace()


  local portal_gui_url = workspace_config.build_ws_portal_gui_url(kong.configuration, workspace)
  local admin_gui_url = workspace_config.build_ws_admin_gui_url(kong.configuration, workspace)
  local developer_email = "developer@example.com"
  local developer_name = "Example Developer"
  local email_token = "exampletoken123"
  local exp_seconds = workspace_config.retrieve(ws_constants.PORTAL_TOKEN_EXP, workspace)
  local token_exp
  if exp_seconds then
    token_exp = portal_utils.humanize_timestamp(exp_seconds)
  else
    token_exp = "PORTAL_TOKEN_EXP MUST BE SET"
  end
  local workspace_name = "default"
  local application_id = "deadbeef-ebdc-4dd8-b744-4370efc8322e"
  local application_name = "Mighty Kong App"

  local tokens_by_path = {
    ["emails/invite.txt"] = {
      ["portal.url"] = portal_gui_url,
      ["email.developer_email"] = developer_email
    },
    ["emails/request-access.txt"] = {
      ["portal.url"] = portal_gui_url,
      ["email.admin_gui_url"] = admin_gui_url,
      ["email.developer_name"] = developer_name,
      ["email.developer_email"] = developer_email,
    },
    ["emails/approved-access.txt"] = {
      ["portal.url"] = portal_gui_url,
      ["email.developer_email"] = developer_email,
      ["email.developer_name"] = developer_name,
    },
    ["emails/password-reset.txt"] = {
      ["portal.url"] = portal_gui_url,
      ["email.developer_email"] = developer_email,
      ["email.developer_name"] = developer_name,
      ["email.token"] = email_token,
      ["email.token_exp"] = token_exp,
      ["email.reset_url"] = portal_gui_url .. "/reset-password?token=" ..
                            email_token,
    },
    ["emails/password-reset-success.txt"] = {
      ["portal.url"] = portal_gui_url,
      ["email.developer_email"] = developer_email,
      ["email.developer_name"] = developer_name,
    },
    ["emails/account-verification-approved.txt"] = {
      ["portal.url"] = portal_gui_url,
      ["email.developer_email"] = developer_email,
      ["email.developer_name"] = developer_name,
    },
    ["emails/account-verification-pending.txt"] = {
      ["portal.url"] = portal_gui_url,
      ["email.developer_email"] = developer_email,
      ["email.developer_name"] = developer_name,
    },
    ["emails/account-verification.txt"] = {
      ["portal.url"] = portal_gui_url,
      ["email.developer_email"] = developer_email,
      ["email.developer_name"] = developer_name,
      ["email.token"] = email_token,
      ["email.verify_url"] = portal_gui_url .. "/account/verify?token=" ..
                                  email_token .. "&email=" .. developer_email,
      ["email.invalidate_url"]= portal_gui_url .. "/account/invalidate-verification?token=" ..
                                email_token .. "&email=" .. developer_email,
    },
    ["emails/application-service-approved.txt"] = {
      ["portal.url"] = portal_gui_url,
      ["email.developer_email"] = developer_email,
      ["email.developer_name"] = developer_name,
      ["email.application_name"] = application_name,
    },
    ["emails/application-service-rejected.txt"] = {
      ["portal.url"] = portal_gui_url,
      ["email.developer_email"] = developer_email,
      ["email.developer_name"] = developer_name,
      ["email.application_name"] = application_name,
    },
    ["emails/application-service-revoked.txt"] = {
      ["portal.url"] = portal_gui_url,
      ["email.developer_email"] = developer_email,
      ["email.developer_name"] = developer_name,
      ["email.application_name"] = application_name,
    },
    ["emails/application-service-pending.txt"] = {
      ["portal.url"] = portal_gui_url,
      ["email.developer_email"] = developer_email,
      ["email.developer_name"] = developer_name,
      ["email.application_name"] = application_name,
    },
    ["emails/application-service-requested.txt"] = {
      ["portal.url"] = portal_gui_url,
      ["email.developer_email"] = developer_email,
      ["email.developer_name"] = developer_name,
      ["email.admin_gui_url"] = admin_gui_url,
      ["email.workspace"] = workspace_name,
      ["email.application_id"] = application_id,
      ["email.application_name"] = application_name,
    },
  }
  return tokens_by_path[path]
end

function _M:replace_tokens(view, tokens)
  for match, replacement in pairs(tokens) do
    match =  "{{%s*" .. match .. "%s*}}"
    view = string.gsub(view, match, replacement)
  end
  return view
end

local function add_meta_matches(developer_email, matches)
  local developer, err = kong.db.developers:select_by_email(developer_email)

  if not developer then
    err = err or "not found"
    ngx.log(ngx.ERR, "unable to fetch developer for meta field replacements in email template: ", err)
    return
  end

  if not developer.meta then
    return
  end

  local workspace = workspaces.get_workspace()
  local dev_meta = cjson.decode(developer.meta)
  local developer_extra_fields = workspace_config.retrieve(PORTAL_DEVELOPER_META_FIELDS, workspace, {decode_json = true})
  local custom_value

  for _, field in ipairs(developer_extra_fields) do
    custom_value = dev_meta[field.title]
    matches["email.developer_meta." .. field.title] = custom_value or ""
  end
end

local function email_handler(self, tokens, file)
  -- can not be required at file scope because ngx.location is not built at start
  local renderer = require "kong.portal.renderer"
  local file_helpers = require "kong.portal.file_helpers"


  self.is_email = true
  renderer.set_render_ctx(self, tokens)
  local view = renderer.compile_layout(tokens)
  -- redudent replacement for edge case of email tokens
  -- (will need to be escaped) in layouts/partials
  view = _M:replace_tokens(view, tokens)

  -- get subject
  if file and file.contents then
    -- parse_file_contents also templates in email tokens
    local headmatter = file_helpers.parse_file_contents(file.contents, tokens)

    if headmatter and headmatter.subject then
      return view, headmatter.subject
    end
  end

  return view
end

function _M.new()
  local conf = kong.configuration or {}

  local client, err = smtp_client.new_smtp_client(conf)
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
  local workspace = workspaces.get_workspace()
  local portal_invite_email = workspace_config.retrieve(ws_constants.PORTAL_INVITE_EMAIL, workspace)

  if not portal_invite_email then
    return nil, {code =  501, message = "portal_invite_email is disabled"}
  end

  local portal_gui_url = workspace_config.build_ws_portal_gui_url(kong.configuration, workspace)
  local portal_emails_from = workspace_config.retrieve(ws_constants.PORTAL_EMAILS_FROM, workspace)
  local portal_emails_reply_to = workspace_config.retrieve(ws_constants.PORTAL_EMAILS_REPLY_TO, workspace)
  local conf = self.conf.portal_invite_email
  local res

  -- send emails individually
  for _, recipient in ipairs(recipients) do

    local html
    local subject
    local path = "emails/invite.txt"

    local file = kong.db.files:select_by_path(path)
    if not file then
      html = fmt(conf.html, portal_gui_url, portal_gui_url, portal_gui_url)
    else
      local matches = {}
      matches["portal.url"] = portal_gui_url
      matches["email.developer_email"] = recipient
      self.path = path
      html, subject = email_handler(self, matches, file)
    end

    local options = {
      from = portal_emails_from,
      reply_to = portal_emails_reply_to,
      subject = subject or fmt(conf.subject, portal_gui_url),
      html = html,
    }

    res = self.client:send({recipient}, options, res)
  end

  return smtp_client.handle_res(res)
end


function _M:access_request(developer_email, developer_name)
  local workspace = workspaces.get_workspace()
  local portal_access_request_email = workspace_config.retrieve(ws_constants.PORTAL_ACCESS_REQUEST_EMAIL, workspace)

  if not portal_access_request_email then
    return nil
  end

  local admin_gui_url = workspace_config.build_ws_admin_gui_url(kong.configuration, workspace)
  local portal_gui_url = workspace_config.build_ws_portal_gui_url(kong.configuration, workspace)
  local portal_emails_from = workspace_config.retrieve(ws_constants.PORTAL_EMAILS_FROM, workspace)
  local portal_emails_reply_to = workspace_config.retrieve(ws_constants.PORTAL_EMAILS_REPLY_TO, workspace)
  local conf = self.conf.portal_access_request_email

  local html
  local subject
  local path = "emails/request-access.txt"

  developer_name = portal_utils.sanitize_developer_name(developer_name)

  local file = kong.db.files:select_by_path(path)
  if not file then
    html = fmt(conf.html, developer_name, developer_email, portal_gui_url, admin_gui_url, admin_gui_url)
  else
    local matches = {}
    matches["portal.url"] = portal_gui_url
    matches["email.admin_gui_url"] = admin_gui_url
    matches["email.developer_name"] = developer_name
    matches["email.developer_email"] = developer_email

    add_meta_matches(developer_email, matches)

    self.path = path
    html, subject = email_handler(self, matches, file)
  end

  local options = {
    from = portal_emails_from,
    reply_to = portal_emails_reply_to,
    subject = subject or fmt(conf.subject, portal_gui_url),
    html = html,
  }

  local res = self.client:send(get_admin_emails(workspace), options)
  return smtp_client.handle_res(res)
end


function _M:approved(recipient, developer_name)
  local workspace = workspaces.get_workspace()
  local portal_approved_email = workspace_config.retrieve(ws_constants.PORTAL_APPROVED_EMAIL, workspace)

  if not portal_approved_email then
    return nil
  end

  local portal_gui_url = workspace_config.build_ws_portal_gui_url(kong.configuration, workspace)
  local portal_emails_from = workspace_config.retrieve(ws_constants.PORTAL_EMAILS_FROM, workspace)
  local portal_emails_reply_to = workspace_config.retrieve(ws_constants.PORTAL_EMAILS_REPLY_TO, workspace)
  local conf = self.conf.portal_approved_email

  local html
  local subject
  local path = "emails/approved-access.txt"

  developer_name = portal_utils.sanitize_developer_name(developer_name)

  local file = kong.db.files:select_by_path(path)
  if not file then
    html = fmt(conf.html, portal_gui_url, portal_gui_url, portal_gui_url)
  else
    local matches = {}
    matches["portal.url"] = portal_gui_url
    matches["email.developer_email"] = recipient
    matches["email.developer_name"] = developer_name

    add_meta_matches(recipient, matches)

    self.path = path
    html, subject = email_handler(self, matches, file)
  end

  local options = {
    from = portal_emails_from,
    reply_to = portal_emails_reply_to,
    subject = subject or fmt(conf.subject, portal_gui_url),
    html = html,
  }

  local res = self.client:send({recipient}, options)
  return smtp_client.handle_res(res)
end

function _M:password_reset(recipient, token, developer_name)
  local workspace = workspaces.get_workspace()
  local portal_reset_email = workspace_config.retrieve(ws_constants.PORTAL_RESET_EMAIL, workspace)

  if not portal_reset_email then
    return nil, {code =  501, message = "portal_reset_email is disabled"}
  end

  local exp_seconds = workspace_config.retrieve(ws_constants.PORTAL_TOKEN_EXP, workspace)
  if not exp_seconds then
    return nil, {code =  500, message = "portal_token_exp is required"}
  end

  local portal_gui_url = workspace_config.build_ws_portal_gui_url(kong.configuration, workspace)
  local portal_emails_from = workspace_config.retrieve(ws_constants.PORTAL_EMAILS_FROM, workspace)
  local portal_emails_reply_to = workspace_config.retrieve(ws_constants.PORTAL_EMAILS_REPLY_TO, workspace)
  local exp_string = portal_utils.humanize_timestamp(exp_seconds)
  local conf = self.conf.portal_reset_email

  local html
  local subject
  local path = "emails/password-reset.txt"

  developer_name = portal_utils.sanitize_developer_name(developer_name)

  local file = kong.db.files:select_by_path(path)
  if not file then
    html = fmt(conf.html, portal_gui_url, token, portal_gui_url, token, exp_string)
  else
    local matches = {}
    matches["portal.url"] = portal_gui_url
    matches["email.developer_email"] = recipient
    matches["email.developer_name"] = developer_name
    matches["email.token"] = token
    matches["email.token_exp"] = exp_string
    matches["email.reset_url"] =  portal_gui_url .. "/reset-password?token=" ..
                                  token

    add_meta_matches(recipient, matches)

    self.path = path
    html, subject = email_handler(self, matches, file)
  end

  local options = {
    from = portal_emails_from,
    reply_to = portal_emails_reply_to,
    subject = subject or fmt(conf.subject, portal_gui_url),
    html = html,
  }

  local res = self.client:send({recipient}, options)
  return smtp_client.handle_res(res)
end

function _M:password_reset_success(recipient, developer_name)
  local workspace = workspaces.get_workspace()
  local portal_reset_success_email = workspace_config.retrieve(ws_constants.PORTAL_RESET_SUCCESS_EMAIL, workspace)

  if not portal_reset_success_email then
    return nil, {code =  501, message = "portal_reset_success_email is disabled"}
  end

  local portal_gui_url = workspace_config.build_ws_portal_gui_url(kong.configuration, workspace)
  local portal_emails_from = workspace_config.retrieve(ws_constants.PORTAL_EMAILS_FROM, workspace)
  local portal_emails_reply_to = workspace_config.retrieve(ws_constants.PORTAL_EMAILS_REPLY_TO, workspace)
  local conf = self.conf.portal_reset_success_email

  local html
  local subject
  local path = "emails/password-reset-success.txt"

  developer_name = portal_utils.sanitize_developer_name(developer_name)

  local file = kong.db.files:select_by_path(path)
  if not file then
    html = fmt(conf.html, portal_gui_url, portal_gui_url, portal_gui_url, portal_gui_url)
  else
    local matches = {}
    matches["portal.url"] = portal_gui_url
    matches["email.developer_email"] = recipient
    matches["email.developer_name"] = developer_name

    add_meta_matches(recipient, matches)

    self.path = path
    html, subject = email_handler(self, matches, file)
  end

  local options = {
    from = portal_emails_from,
    reply_to = portal_emails_reply_to,
    subject = subject or fmt(conf.subject, portal_gui_url),
    html = html,
  }

  local res = self.client:send({recipient}, options)
  return smtp_client.handle_res(res)
end

function _M:account_verification_email(recipient, token, developer_name)
  local workspace = workspaces.get_workspace()

  local portal_gui_url = workspace_config.build_ws_portal_gui_url(kong.configuration, workspace)
  local portal_emails_from = workspace_config.retrieve(ws_constants.PORTAL_EMAILS_FROM, workspace)
  local portal_emails_reply_to = workspace_config.retrieve(ws_constants.PORTAL_EMAILS_REPLY_TO, workspace)
  local conf = self.conf.portal_account_verification_email

  local html
  local subject
  local path = "emails/account-verification.txt"

  developer_name = portal_utils.sanitize_developer_name(developer_name)

  local file = kong.db.files:select_by_path(path)
  if not file then
    html = fmt(conf.html, portal_gui_url,
      portal_gui_url, token, recipient,
      portal_gui_url, token,
      portal_gui_url, token, recipient,
      portal_gui_url, token)
  else
    local matches = {}
    matches["portal.url"] = portal_gui_url
    matches["email.developer_email"] = recipient
    matches["email.developer_name"] = developer_name
    matches["email.token"] = token
    matches["email.verify_url"] = portal_gui_url ..
                                  "/account/verify?token=" ..
                                  token .. "&email=" .. recipient
    matches["email.invalidate_url"] = portal_gui_url ..
                                  "/account/invalidate-verification?token=" ..
                                   token .. "&email=" .. recipient

    add_meta_matches(recipient, matches)

    self.path = path
    html, subject = email_handler(self, matches, file)
  end

  local options = {
    from = portal_emails_from,
    reply_to = portal_emails_reply_to,
    subject = subject or fmt(conf.subject, portal_gui_url),
    html = html,
  }

  local res = self.client:send({recipient}, options)
  return smtp_client.handle_res(res)
end

function _M:account_verification_success_approved(recipient, developer_name)
  local workspace = workspaces.get_workspace()

  local portal_gui_url = workspace_config.build_ws_portal_gui_url(kong.configuration, workspace)
  local portal_emails_from = workspace_config.retrieve(ws_constants.PORTAL_EMAILS_FROM, workspace)
  local portal_emails_reply_to = workspace_config.retrieve(ws_constants.PORTAL_EMAILS_REPLY_TO, workspace)
  local conf = self.conf.portal_account_verification_success_approved_email

  local html
  local subject
  local path = "emails/account-verification-approved.txt"

  developer_name = portal_utils.sanitize_developer_name(developer_name)

  local file = kong.db.files:select_by_path(path)
  if not file then
    html = fmt(conf.html, portal_gui_url, portal_gui_url, portal_gui_url, portal_gui_url)
  else
    local matches = {}
    matches["portal.url"] = portal_gui_url
    matches["email.developer_email"] = recipient
    matches["email.developer_name"] = developer_name

    add_meta_matches(recipient, matches)

    self.path = path
    html, subject = email_handler(self, matches, file)
  end

  local options = {
    from = portal_emails_from,
    reply_to = portal_emails_reply_to,
    subject = subject or fmt(conf.subject, portal_gui_url),
    html = html,
  }

  local res = self.client:send({recipient}, options)
  return smtp_client.handle_res(res)
end

function _M:account_verification_success_pending(recipient, developer_name)
  local workspace = workspaces.get_workspace()

  local portal_gui_url = workspace_config.build_ws_portal_gui_url(kong.configuration, workspace)
  local portal_emails_from = workspace_config.retrieve(ws_constants.PORTAL_EMAILS_FROM, workspace)
  local portal_emails_reply_to = workspace_config.retrieve(ws_constants.PORTAL_EMAILS_REPLY_TO, workspace)
  local conf = self.conf.portal_account_verification_success_pending_email

  local html
  local subject
  local path = "emails/account-verification-pending.txt"

  developer_name = portal_utils.sanitize_developer_name(developer_name)

  local file = kong.db.files:select_by_path(path)
  if not file then
    html = fmt(conf.html, portal_gui_url, portal_gui_url, portal_gui_url, portal_gui_url)
  else
    local matches = {}
    matches["portal.url"] = portal_gui_url
    matches["email.developer_email"] = recipient
    matches["email.developer_name"] = developer_name

    add_meta_matches(recipient, matches)

    self.path = path
    html, subject = email_handler(self, matches, file)
  end

  local options = {
    from = portal_emails_from,
    reply_to = portal_emails_reply_to,
    subject = subject or fmt(conf.subject, portal_gui_url),
    html = html,
  }

  local res = self.client:send({recipient}, options)
  return smtp_client.handle_res(res)
end

function _M:application_service_requested(developer_name, developer_email,
                                          application_name, application_id)
  local workspace = workspaces.get_workspace()
  local portal_application_request_email = workspace_config.retrieve(ws_constants.PORTAL_APPLICATION_REQUEST_EMAIL, workspace)

  if not portal_application_request_email then
    return nil
  end

  local admin_gui_url = workspace_config.build_ws_admin_gui_url(kong.configuration, workspace)
  local portal_gui_url = workspace_config.build_ws_portal_gui_url(kong.configuration, workspace)
  local portal_emails_from = workspace_config.retrieve(ws_constants.PORTAL_EMAILS_FROM, workspace)
  local portal_emails_reply_to = workspace_config.retrieve(ws_constants.PORTAL_EMAILS_REPLY_TO, workspace)
  local conf = self.conf.portal_application_service_requested_email

  local html
  local subject
  local path = "emails/application-service-requested.txt"

  developer_name = portal_utils.sanitize_developer_name(developer_name)

  local file = kong.db.files:select_by_path(path)
  if not file then
    html = fmt(conf.html, developer_name, developer_email, portal_gui_url,
               workspace.name, application_name,
               admin_gui_url, application_id,
               admin_gui_url, application_id)
  else
    local matches = {}
    matches["portal.url"] = portal_gui_url
    matches["email.admin_gui_url"] = admin_gui_url
    matches["email.developer_email"] = developer_email
    matches["email.developer_name"] = developer_name
    matches["email.application_name"] = application_name
    matches["email.application_id"] = application_id
    matches["email.workspace"] = workspace.name

    add_meta_matches(developer_email, matches)

    self.path = path
    html, subject = email_handler(self, matches, file)
  end

  local options = {
    from = portal_emails_from,
    reply_to = portal_emails_reply_to,
    subject = subject or fmt(conf.subject, portal_gui_url, developer_email),
    html = html,
  }

  local res = self.client:send(get_admin_emails(workspace), options)
  return smtp_client.handle_res(res)
end

function _M:application_service_status_change(template_path, fallback_template, recipient,
                                              developer_name, application_name)
  local workspace = workspaces.get_workspace()
  local portal_application_status_email = workspace_config.retrieve(ws_constants.PORTAL_APPLICATION_STATUS_EMAIL, workspace)

  if not portal_application_status_email then
    return nil
  end

  local portal_gui_url = workspace_config.build_ws_portal_gui_url(kong.configuration, workspace)
  local portal_emails_from = workspace_config.retrieve(ws_constants.PORTAL_EMAILS_FROM, workspace)
  local portal_emails_reply_to = workspace_config.retrieve(ws_constants.PORTAL_EMAILS_REPLY_TO, workspace)
  local conf = fallback_template

  local html
  local subject

  developer_name = portal_utils.sanitize_developer_name(developer_name)

  local file = kong.db.files:select_by_path(template_path)
  if not file then
    html = fmt(conf.html, portal_gui_url, portal_gui_url, application_name)
  else
    local matches = {}
    matches["portal.url"] = portal_gui_url
    matches["email.developer_email"] = recipient
    matches["email.developer_name"] = developer_name
    matches["email.application_name"] = application_name

    add_meta_matches(recipient, matches)

    self.path = template_path
    html, subject = email_handler(self, matches, file)
  end

  local options = {
    from = portal_emails_from,
    reply_to = portal_emails_reply_to,
    subject = subject or fmt(conf.subject, portal_gui_url),
    html = html,
  }

  local res = self.client:send({recipient}, options)
  return smtp_client.handle_res(res)
end

function _M:application_service_approved(recipient, developer_name, application_name)
  developer_name = portal_utils.sanitize_developer_name(developer_name)
  return self:application_service_status_change(
    "emails/application-service-approved.txt",
    self.conf.portal_application_service_approved_email,
    recipient, developer_name, application_name
  )
end

function _M:application_service_rejected(recipient, developer_name, application_name)
  developer_name = portal_utils.sanitize_developer_name(developer_name)
  return self:application_service_status_change(
    "emails/application-service-rejected.txt",
    self.conf.portal_application_service_rejected_email,
    recipient, developer_name, application_name
  )
end

function _M:application_service_pending(recipient, developer_name, application_name)
  developer_name = portal_utils.sanitize_developer_name(developer_name)
  return self:application_service_status_change(
   "emails/application-service-pending.txt",
   self.conf.portal_application_service_pending_email,
   recipient, developer_name, application_name
  )
end

function _M:application_service_revoked(recipient, developer_name, application_name)
  developer_name = portal_utils.sanitize_developer_name(developer_name)
  return self:application_service_status_change(
   "emails/application-service-revoked.txt",
   self.conf.portal_application_service_revoked_email,
   recipient, developer_name, application_name
  )
end

return _M
