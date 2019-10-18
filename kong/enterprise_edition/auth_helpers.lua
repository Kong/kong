local kong  = kong


local _M = {}
local attempt_ttl = 60 * 60 * 24 * 7 -- one week


-- Plugin response handler from login attempts
-- @tparam table|boolean|nil plugin_res
-- @tparam table|nil entity - admin or developer entity including entity.consumer
-- @tparam number max - max attempts allowed
function _M.plugin_res_handler(plugin_res, entity, max)
  local ip = kong.client.get_ip()

  if type(plugin_res) == 'table' and
    plugin_res.status == 401
  then
    local _, err = _M.unauthorized_login_attempt(entity, ip, max)
    if err then
      kong.response.exit(500, { message = "An unexpected error occurred" })
    end

    -- unauthorized login attempt, use response from plugin to exit
    kong.response.exit(plugin_res.status, { message = plugin_res.message })
  end

  local _, err = _M.successful_login_attempt(entity, ip, max)
  if err then
    kong.response.exit(500, { message = "An unexpected error occurred" })
  end
end


-- Logic for login_attempts once user has been marked unauthorized
-- @tparam table entity - admin or developer entity including entity.consumer
-- @tparam string ip - ip address of login attempt
-- @tparam number max - max attempts allowed
function _M.unauthorized_login_attempt(entity, ip, max)
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
        [ip] = 1
      }
    }, { ttl = attempt_ttl })

    if err then
      kong.log.err("error inserting login_attempts", err)
      return nil, err
    end

    return
  end

  -- Additional attempts
  attempt.attempts[ip] = attempt.attempts[ip] + 1
  local _, err = login_attempts:update({consumer = consumer}, {
    attempts = attempt.attempts
  })

  if err then
    kong.log.err("error updating login_attempts", err)
    return nil, err
  end

  -- Final attempt
  if attempt.attempts[ip] >= max then
    local user = entity.username or entity.email
    kong.log.warn("Unauthorized, and login attempts exceed max for user:" ..
      user .. ", account locked at ip address:", ip)
  end
end


-- Logic for login_attempts once user successfully logs in
-- @tparam table entity - admin or developer entity including entity.consumer
-- @tparam string ip - ip address of login attempt
-- @tparam number max - max attempts allowed
function _M.successful_login_attempt(entity, ip, max)
  if max == 0 then return end

  local login_attempts = kong.db.login_attempts
  local consumer = entity.consumer
  local attempt, err = login_attempts:select({consumer = consumer})

  if err then
    kong.log.err("error fetching login_attempts", err)
    return nil, err
  end

  -- no failed attempts, good to proceed
  if not attempt or not attempt.attempts[ip] then
    return
  end

  -- User is authorized, but can be denied access if attempts exceed max
  if attempt.attempts[ip] >= max then
    local user = entity.username or entity.email
    kong.log.warn("Successful authorization, but login attempts exceed max for user:"
     .. user .. ", account locked at ip address:", ip)
    -- use the same response from basic-auth plugin
    kong.response.exit(401, { message = "Invalid authentication credentials" })
  end

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


return _M
