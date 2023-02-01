local kong_session = require "kong.plugins.session.session"


local ngx = ngx
local kong = kong
local type = type
local assert = assert


local function get_authenticated_groups()
  local authenticated_groups = ngx.ctx.authenticated_groups
  if authenticated_groups == nil then
    return
  end

  assert(type(authenticated_groups) == "table",
         "invalid authenticated_groups, a table was expected")

  return authenticated_groups
end


local _M = {}


function _M.execute(conf)
  local credential = kong.client.get_credential()
  local consumer = kong.client.get_consumer()

  if not credential then
    -- don't open sessions for anonymous users
    kong.log.debug("anonymous: no credential")
    return
  end

  local credential_id = credential.id

  local subject
  local consumer_id
  if consumer then
    consumer_id = consumer.id
    subject = consumer.username or consumer.custom_id or consumer_id
  end

  -- if session exists and the data in the session matches the ctx then
  -- don't worry about saving the session data or sending cookie
  local session = kong.ctx.shared.authenticated_session
  if session then
    local session_consumer_id, session_credential_id = kong_session.get_session_data(session)
    if session_credential_id == credential_id and
       session_consumer_id   == consumer_id
    then
      return
    end
  end

  -- session is no longer valid
  -- create new session and save the data / send the Set-Cookie header
  if consumer_id then
    local groups = get_authenticated_groups()
    if not session then
      session = kong_session.open_session(conf)
    end

    kong_session.set_session_data(session,
                                  consumer_id,
                                  credential_id or consumer_id,
                                  groups)

    session:set_subject(subject)

    local ok, err = session:save()
    if not ok then
      if err then
        kong.log.err("session save failed (", err, ")")
      else
        kong.log.err("session save failed")
      end
    end

    session:set_response_headers()
  end
end


return _M
