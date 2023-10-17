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

local _M = {}

-- By default, the attempts_ttl is one week (60 * 60 * 24 * 7)
local LOGIN_ATTEMPTS_TTL = 604800

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

-- Passwordqc wrapper function
-- @tparam string new_pass
-- @tparam string|nil old_pass
-- @tparam table|nil opts - password quality control options
function _M.check_password_complexity(new_pass, old_pass, opts)
  opts = PASSWD_COMPLEXITY_PRESET[opts["kong-preset"]] or opts

  return passwdqc.check(new_pass, old_pass, opts)
end

-- Plugin response handler from login attempts
-- @tparam table|boolean|nil plugin_res
-- @tparam table|nil entity - admin or developer entity including entity.consumer
-- @tparam number max - max attempts allowed
function _M.plugin_res_handler(plugin_res, entity, max)
  if type(plugin_res) == 'table' and
    plugin_res.status == 401
  then
    local _, err = _M.unauthorized_login_attempt(entity, max)
    if err then
      kong.response.exit(500, { message = "An unexpected error occurred" })
    end

    -- unauthorized login attempt, use response from plugin to exit
    kong.response.exit(plugin_res.status, { message = plugin_res.message })
  end

  local _, err = _M.successful_login_attempt(entity, max)
  if err then
    kong.response.exit(500, { message = "An unexpected error occurred" })
  end
end


-- Logic for login_attempts once user has been marked unauthorized
-- @tparam table entity - admin or developer entity including entity.consumer
-- @tparam number max - max attempts allowed
function _M.unauthorized_login_attempt(entity, max)
  if max == 0 then return end

  local login_attempts = kong.db.login_attempts
  local consumer = entity.consumer
  local attempt, err = login_attempts:select({ consumer = consumer })

  if err then
    kong.log.err("error fetching login_attempts", err)
    return nil, err
  end

  -- First attempt
  if not attempt then
    local _, err = login_attempts:insert({
      consumer = consumer,
      attempts = {
        [LOGIN_ATTEMPTS_IP] = 1
      }
    }, { ttl = LOGIN_ATTEMPTS_TTL })

    if err then
      kong.log.err("error inserting login_attempts", err)
      return nil, err
    end

    return
  end

  -- Additional attempts. For upgrades, LOGIN_ATTEMPTS_IP may not be in the table
  attempt.attempts[LOGIN_ATTEMPTS_IP] = (attempt.attempts[LOGIN_ATTEMPTS_IP] or 0) + 1
  local _, err = login_attempts:update({consumer = consumer}, {
    attempts = attempt.attempts
  })

  if err then
    kong.log.err("error updating login_attempts", err)
    return nil, err
  end

  -- Final attempt
  if attempt.attempts[LOGIN_ATTEMPTS_IP] >= max then
    local user = entity.username or entity.email
    kong.log.warn("Unauthorized: login attempts exceed max for user " .. user)
  end
end


-- Logic for login_attempts once user successfully logs in
-- @tparam table entity - admin or developer entity including entity.consumer
-- @tparam number max - max attempts allowed
function _M.successful_login_attempt(entity, max)
  if max == 0 then return end

  local login_attempts = kong.db.login_attempts
  local consumer = entity.consumer
  local attempt, err = login_attempts:select({consumer = consumer})

  if err then
    kong.log.err("error fetching login_attempts", err)
    return nil, err
  end

  -- no failed attempts, good to proceed
  if not attempt or not attempt.attempts[LOGIN_ATTEMPTS_IP] then
    return
  end

  -- User is authorized, but can be denied access if attempts exceed max
  if attempt.attempts[LOGIN_ATTEMPTS_IP] >= max then
    local user = entity.username or entity.email
    kong.log.warn("Authorized: login attempts exceed max for user " .. user)
    -- use the same response from basic-auth plugin
    kong.response.exit(401, { message = "Unauthorized" })
  end

  -- Successful login before hitting max clears the counter
  local _, err = login_attempts:delete({consumer = consumer})

  if err then
    kong.log.err("error updating login_attempts", err)
    return nil, err
  end
end


function _M.reset_attempts(consumer)
  local _, err = kong.db.login_attempts:delete({consumer = consumer})

  if err then
    kong.log.err("error resetting attempts", err)
    return nil, err
  end
end

  --- Verify an admin/developers's basic auth credential password checking old vs. new
  -- @param `db` database strategy must contain consumer
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


return _M
