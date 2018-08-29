local mail       = require "resty.mail"
local utils      = require "kong.portal.utils"
local pl_tablex  = require "pl.tablex"
local log         = ngx.log
local INFO        = ngx.INFO


local _M = {}
local mt = { __index = _M }


_M.INVALID_EMAIL = "Invalid email"
_M.SEND_ERR      = "Error sending email"
_M.LOG_PREFIX    = "[smtp-client]"


-- conf = {
--   host =            default localhost
--   port =            default 25
--   starttls =        default nil
--   ssl =             default nil
--   username =        default nil
--   password =        default nil
--   auth_type =       default nil
--   domain =          default localhost.localdomain
--   timeout_connect = default 60000 (ms)
--   timeout_send =    default 60000 (ms)
--   timeout_read  =   default 60000 (ms)
-- }
function _M.new(conf, smtp_mock)
  conf = conf or {}
  local mailer, err

  if smtp_mock then
    mailer = {
      send = function()
        return true
      end,
    }
  else
    mailer, err = mail.new(conf)
    if err then
      return nil, err
    end
  end

  local self = {
    mailer = mailer,
    smtp_mock = smtp_mock,
  }

  return setmetatable(self, mt)
end


function _M.handle_res(res)
  local code = res.code
  res.code = nil

  if res.sent.count < 1 then
    return nil, {message = res, code = code or 500}
  end

  return res
end


function _M:send(emails, base_options, res)
  local res            = res or self:init_email_res()
  local emails_to_send = {}
  local seen_emails    = {}
  local sent           = res.sent
  local error          = res.error

  -- loop over emails, filter out invalid emails
  for _, email in ipairs(emails) do
    -- skip duplicate emails
    if not seen_emails[email] and not sent.emails[email]
                              and not error.emails[email] then
      local ok, err = utils.validate_email(email)
      if not ok then
        log(INFO, _M.LOG_PREFIX, _M.INVALID_EMAIL .. ": " .. email .. ": " .. err)
        error.emails[email] = _M.INVALID_EMAIL .. ": " .. err
        error.count = error.count + 1
      else
        table.insert(emails_to_send, email)
      end

      -- mark email as seen
      seen_emails[email] = true
    end
  end

  if next(emails_to_send) == nil then
    res.code = 400
    return res
  end

  -- send the batch of emails (single send)
  local send_options = pl_tablex.union({ to = emails_to_send }, base_options)
  local ok, err      = self.mailer:send(send_options)

  -- iterate over sent emails and record response
  for _, email in pairs(emails_to_send) do
    if not ok then
      -- log the full error, only return generic SEND_ERR msg
      log(INFO, _M.LOG_PREFIX, _M.SEND_ERR .. ": " .. email .. ": " .. err)
      error.emails[email] = _M.SEND_ERR
      error.count = error.count + 1
    else
      sent.emails[email] = true
      sent.count = sent.count + 1
    end
  end

  return res
end

function _M:init_email_res()
  local res = {
    sent  = {emails = {}, count = 0},
    error = {emails = {}, count = 0},
  }

  -- if smtp is mocked, attach flag to response
  if self.smtp_mock then
    res.smtp_mock = true
  end

  return res
end


return _M
