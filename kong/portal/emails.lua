-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local smtp_client  = require "kong.enterprise_edition.smtp_client"
local portal_utils = require "kong.portal.utils"
local singletons   = require "kong.singletons"
local workspaces = require "kong.workspaces"
local workspace_config = require "kong.portal.workspace_config"
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
      </p>
        <a href="%s/account/verify?token=%s&email=%s">verify account</a>
      </p>
      <p>
        If you didn't make this request, please click the link below to invalidate this request.
      </p>
      </p>
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
  }
}

function _M:get_example_email_tokens(path)
  local workspace = workspaces.get_workspace()


  local portal_gui_url = workspace_config.build_ws_portal_gui_url(singletons.configuration, workspace)
  local admin_gui_url = workspace_config.build_ws_admin_gui_url(singletons.configuration, workspace)
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
  local conf = singletons.configuration or {}

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

  local portal_gui_url = workspace_config.build_ws_portal_gui_url(singletons.configuration, workspace)
  local portal_emails_from = workspace_config.retrieve(ws_constants.PORTAL_EMAILS_FROM, workspace)
  local portal_emails_reply_to = workspace_config.retrieve(ws_constants.PORTAL_EMAILS_REPLY_TO, workspace)
  local conf = self.conf.portal_invite_email
  local res

  -- send emails individually
  for _, recipient in ipairs(recipients) do

    local html
    local subject
    local path = "emails/invite.txt"

    local file = singletons.db.files:select_by_path(path)
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

  local admin_gui_url = workspace_config.build_ws_admin_gui_url(singletons.configuration, workspace)
  local portal_gui_url = workspace_config.build_ws_portal_gui_url(singletons.configuration, workspace)
  local portal_emails_from = workspace_config.retrieve(ws_constants.PORTAL_EMAILS_FROM, workspace)
  local portal_emails_reply_to = workspace_config.retrieve(ws_constants.PORTAL_EMAILS_REPLY_TO, workspace)
  local conf = self.conf.portal_access_request_email

  local html
  local subject
  local path = "emails/request-access.txt"

  local file = singletons.db.files:select_by_path(path)
  if not file then
    html = fmt(conf.html, developer_name, developer_email, portal_gui_url, admin_gui_url, admin_gui_url)
  else
    local matches = {}
    matches["portal.url"] = portal_gui_url
    matches["email.admin_gui_url"] = admin_gui_url
    matches["email.developer_name"] = developer_name
    matches["email.developer_email"] = developer_email
    self.path = path
    html, subject = email_handler(self, matches, file)
  end

  local options = {
    from = portal_emails_from,
    reply_to = portal_emails_reply_to,
    subject = subject or fmt(conf.subject, portal_gui_url),
    html = html,
  }

  local res = self.client:send(singletons.configuration.smtp_admin_emails, options)
  return smtp_client.handle_res(res)
end


function _M:approved(recipient, developer_name)
  local workspace = workspaces.get_workspace()
  local portal_approved_email = workspace_config.retrieve(ws_constants.PORTAL_APPROVED_EMAIL, workspace)

  if not portal_approved_email then
    return nil
  end

  local portal_gui_url = workspace_config.build_ws_portal_gui_url(singletons.configuration, workspace)
  local portal_emails_from = workspace_config.retrieve(ws_constants.PORTAL_EMAILS_FROM, workspace)
  local portal_emails_reply_to = workspace_config.retrieve(ws_constants.PORTAL_EMAILS_REPLY_TO, workspace)
  local conf = self.conf.portal_approved_email

  local html
  local subject
  local path = "emails/approved-access.txt"

  local file = singletons.db.files:select_by_path(path)
  if not file then
    html = fmt(conf.html, portal_gui_url, portal_gui_url, portal_gui_url)
  else
    local matches = {}
    matches["portal.url"] = portal_gui_url
    matches["email.developer_email"] = recipient
    matches["email.developer.name"] = developer_name
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

  local portal_gui_url = workspace_config.build_ws_portal_gui_url(singletons.configuration, workspace)
  local portal_emails_from = workspace_config.retrieve(ws_constants.PORTAL_EMAILS_FROM, workspace)
  local portal_emails_reply_to = workspace_config.retrieve(ws_constants.PORTAL_EMAILS_REPLY_TO, workspace)
  local exp_string = portal_utils.humanize_timestamp(exp_seconds)
  local conf = self.conf.portal_reset_email

  local html
  local subject
  local path = "emails/password-reset.txt"

  local file = singletons.db.files:select_by_path(path)
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

  local portal_gui_url = workspace_config.build_ws_portal_gui_url(singletons.configuration, workspace)
  local portal_emails_from = workspace_config.retrieve(ws_constants.PORTAL_EMAILS_FROM, workspace)
  local portal_emails_reply_to = workspace_config.retrieve(ws_constants.PORTAL_EMAILS_REPLY_TO, workspace)
  local conf = self.conf.portal_reset_success_email

  local html
  local subject
  local path = "emails/password-reset-success.txt"

  local file = singletons.db.files:select_by_path(path)
  if not file then
    html = fmt(conf.html, portal_gui_url, portal_gui_url, portal_gui_url, portal_gui_url)
  else
    local matches = {}
    matches["portal.url"] = portal_gui_url
    matches["email.developer_email"] = recipient
    matches["email.developer_name"] = developer_name
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

  local portal_gui_url = workspace_config.build_ws_portal_gui_url(singletons.configuration, workspace)
  local portal_emails_from = workspace_config.retrieve(ws_constants.PORTAL_EMAILS_FROM, workspace)
  local portal_emails_reply_to = workspace_config.retrieve(ws_constants.PORTAL_EMAILS_REPLY_TO, workspace)
  local conf = self.conf.portal_account_verification_email

  local html
  local subject
  local path = "emails/account-verification.txt"

  local file = singletons.db.files:select_by_path(path)
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

  local portal_gui_url = workspace_config.build_ws_portal_gui_url(singletons.configuration, workspace)
  local portal_emails_from = workspace_config.retrieve(ws_constants.PORTAL_EMAILS_FROM, workspace)
  local portal_emails_reply_to = workspace_config.retrieve(ws_constants.PORTAL_EMAILS_REPLY_TO, workspace)
  local conf = self.conf.portal_account_verification_success_approved_email

  local html
  local subject
  local path = "emails/account-verification-approved.txt"

  local file = singletons.db.files:select_by_path(path)
  if not file then
    html = fmt(conf.html, portal_gui_url, portal_gui_url, portal_gui_url, portal_gui_url)
  else
    local matches = {}
    matches["portal.url"] = portal_gui_url
    matches["email.developer_email"] = recipient
    matches["email.developer_name"] = developer_name
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

  local portal_gui_url = workspace_config.build_ws_portal_gui_url(singletons.configuration, workspace)
  local portal_emails_from = workspace_config.retrieve(ws_constants.PORTAL_EMAILS_FROM, workspace)
  local portal_emails_reply_to = workspace_config.retrieve(ws_constants.PORTAL_EMAILS_REPLY_TO, workspace)
  local conf = self.conf.portal_account_verification_success_pending_email

  local html
  local subject
  local path = "emails/account-verification-pending.txt"

  local file = singletons.db.files:select_by_path(path)
  if not file then
    html = fmt(conf.html, portal_gui_url, portal_gui_url, portal_gui_url, portal_gui_url)
  else
    local matches = {}
    matches["portal.url"] = portal_gui_url
    matches["email.developer_email"] = recipient
    matches["email.developer_name"] = developer_name
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

return _M
