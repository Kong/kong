-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local passwdqc = require "resty.passwdqc"
local basicauth_crypto = require "kong.plugins.basic-auth.crypto"

local kong = kong
local null = ngx.null
local assert = assert

local _helpers = {}

-- login_attempts.attempts is a map of counts per IP address.
-- For now, we don't lock out per IP, so just pick one for the map entry.
local LOGIN_ATTEMPTS_IP = "127.0.0.1"

-- user-friendly preset can be added to this table
-- Kong Manager only supports the keywords: "min", "max" and "passphrase"
-- since the existed password will be supported regardless it's complexity
local PASSWD_COMPLEXITY_PRESET = {
  min_8  = { min = "disabled,disabled,8,8,8" },
  min_12 = { min = "disabled,disabled,12,12,12" },
  min_20 = { min = "disabled,disabled,20,20,20" },
}

-- Plugin response handler from login attempts
-- @tparam table|boolean|nil plugin_res
-- @tparam table|nil entity - admin or developer entity including entity.consumer
function _helpers:plugin_res_handler(plugin_res, entity)
  if type(plugin_res) == 'table' and plugin_res.status == 401 then
    local _, err = self:unsuccessful_login_attempt(entity)
    if err then
      kong.response.exit(500, { message = "An unexpected error occurred" })
    end

    -- unauthorized login attempt, use response from plugin to exit
    kong.response.exit(plugin_res.status, { message = plugin_res.message })
  end

  local _, err = self:successful_login_attempt(entity)
  if err then
    kong.response.exit(500, { message = "An unexpected error occurred" })
  end
end

function _helpers:is_exceed_max_attempts(attempt)
  if self.max_attempts == 0 or not attempt then
    return false
  end

  return attempt.attempts[LOGIN_ATTEMPTS_IP] >= self.max_attempts
end

function _helpers:retrieve_login_attempts(admin)
  local login_attempts = kong.db.login_attempts
  local attempt, err = login_attempts:select({ consumer = admin.consumer, attempt_type = self.attempt_type })

  if err then
    kong.log.err("error fetching login_attempts", err)
    return kong.response.exit(500, { message = "An unexpected error occurred" })
  end
  
  return attempt
end

-- Logic for login_attempts once user has been marked unauthorized
-- @tparam table entity - admin or developer entity including entity.consumer
function _helpers:unsuccessful_login_attempt(entity)
  if self.max_attempts == 0 then return end

  local login_attempts = kong.db.login_attempts
  local attempt = self:retrieve_login_attempts(entity)

  -- First attempt
  if not attempt then
    local _, err = login_attempts:delete({ consumer = entity.consumer, attempt_type = self.attempt_type },
      { skip_ttl = true })

    if err then
      kong.log.err("error deleting login_attempts", err)
      return nil, err
    end
    
    local _, err = login_attempts:insert({
      consumer = entity.consumer,
      attempt_type = self.attempt_type,
      attempts = {
        [LOGIN_ATTEMPTS_IP] = 1
      }
    }, { ttl = self.ttl })

    if err then
      kong.log.err("error inserting login_attempts", err)
      return nil, err
    end

    return
  end

  -- Additional attempts. For upgrades, LOGIN_ATTEMPTS_IP may not be in the table
  attempt.attempts[LOGIN_ATTEMPTS_IP] = (attempt.attempts[LOGIN_ATTEMPTS_IP] or 0) + 1
  local _, err = login_attempts:update({ consumer = entity.consumer, attempt_type = self.attempt_type }, {
    attempts = attempt.attempts
  })

  if err then
    kong.log.err("error updating login_attempts", err)
    return nil, err
  end

  -- Final attempt
  self.final_handler(self, entity, attempt, false)
end


-- Logic for login_attempts once user successfully logs in or change password
-- @tparam table entity - admin or developer entity including entity.consumer
function _helpers:successful_login_attempt(entity)
  if self.max_attempts == 0 then return end

  local attempt = self:retrieve_login_attempts(entity)

  -- no failed attempts, good to proceed
  if not attempt or not attempt.attempts[LOGIN_ATTEMPTS_IP] then
    return
  end

  -- -- User is authorized, but can be denied access if attempts exceed max
  self.final_handler(self, entity, attempt, true)
  -- Successful login before hitting max clears the counter
  local _, err = kong.db.login_attempts:delete({ consumer = entity.consumer, attempt_type = self.attempt_type },
    { skip_ttl = true })
  if err then 
    kong.log.err("error deleting login_attempts", err)
    return nil, err	
  end
end

function _helpers:reset_attempts(consumer)
  local _, err = kong.db.login_attempts:delete({ consumer = consumer, attempt_type = self.attempt_type },
    { skip_ttl = true })

  if err then
    kong.log.err("error deleting login_attempts", err)
    return nil, err
  end
end

local _M = {}

-- Passwordqc wrapper function
-- @tparam string new_pass
-- @tparam string|nil old_pass
-- @tparam table|nil opts - password quality control options
function _M.check_password_complexity(new_pass, old_pass, opts)
  opts = PASSWD_COMPLEXITY_PRESET[opts["kong-preset"]] or opts

  return passwdqc.check(new_pass, old_pass, opts)
end

--- Verify an admin/developers's basic auth credential password checking old vs new
-- @param `user` must contain consumer with database strategy
-- @param{type=string} `old_password`
-- @param{type=string} `new_password`
--
-- @return{type=table} credential
-- @return{type=string} bad_request_message
-- @return error
function _M.verify_password(user, old_password, new_password)
  if not old_password then
    return nil, "Must include old_password"
  end

  if not new_password or new_password == old_password then
    return nil, "Passwords cannot be the same"
  end

  local creds, err = kong.db.basicauth_credentials:page_for_consumer(
    user.consumer,
    nil,
    nil,
    { workspace = null }
  )
  if err then
    return nil, nil, err
  end

  if creds[1] then
    local digest, err = basicauth_crypto.hash(creds[1].consumer.id,
      old_password)

    if err then
      kong.log.err(err)
      return nil, nil, err
    end

    local valid = creds[1].password == digest

    if not valid then
      return nil, "Old password is invalid"
    end

    return creds[1]
  end

  return nil, "Bad request"
end

-- By default, the attempts_ttl for login is 7 days (60 * 60 * 24 * 7)
-- the attempts_ttl for change password is 1 day (60 * 60 * 24 * 1)
local LOGIN_ATTEMPTS_CONFIGURATIONS = {
  login = {
    default_ttl = 604800,
    configurations = {
      attempt = "admin_gui_auth_login_attempts",
      ttl     = "admin_gui_auth_login_attempts_ttl",
    },
    final_handler = function(self, entity, attempt, success)
      if self:is_exceed_max_attempts(attempt) then
        local user = entity.username or entity.email
        kong.log.warn("Authorized: login attempts exceed max for user " .. user)
        -- use the same response from basic-auth plugin
        if success then
          kong.response.exit(401, { message = "Unauthorized" })
        end
      end
    end,
  },
  change_password = {
    default_ttl = 86400,
    configurations = {
      attempt = "admin_gui_auth_change_password_attempts",
      ttl     = "admin_gui_auth_change_password_ttl",
    },
    final_handler = function() end,
  }
}

function _M.new(attempts_config)
  attempts_config = attempts_config or {}

  local attempt_type = attempts_config.attempt_type
  assert(attempt_type == 'login' or attempt_type == 'change_password',
    "failed to new auth_helpers, attempt_type must be specified, either 'login' or 'change_password'")

  local config = LOGIN_ATTEMPTS_CONFIGURATIONS[attempt_type]
  local configurations = attempts_config.configurations or config.configurations

  local self = {
    attempt_type = attempt_type,
    max_attempts = kong.configuration[configurations.attempt] or 0,
    ttl = kong.configuration[configurations.ttl] or config.default_ttl,
    final_handler = config.final_handler,
  }

  return setmetatable(self, { __index = _helpers })
end

return _M
