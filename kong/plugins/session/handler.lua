local access = require "kong.plugins.session.access"
local session = require "kong.plugins.session.session"


local kong = kong


local KongSessionHandler = {
  PRIORITY = 1900,
  VERSION = "2.1.1",
}


function KongSessionHandler:header_filter(conf)
  local credential = kong.client.get_credential()
  local consumer = kong.client.get_consumer()

  if not credential then
    -- don't open sessions for anonymous users
    kong.log.debug("anonymous: no credential.")
    return
  end

  local credential_id = credential.id
  local consumer_id = consumer and consumer.id
  local s = kong.ctx.shared.authenticated_session

  -- if session exists and the data in the session matches the ctx then
  -- don't worry about saving the session data or sending cookie
  if s and s.present then
    local cid, cred_id = session.retrieve_session_data(s)
    if cred_id == credential_id and cid == consumer_id
    then
      return
    end
  end

  -- session is no longer valid
  -- create new session and save the data / send the Set-Cookie header
  if consumer_id then
    s = s or session.open_session(conf)
    session.store_session_data(s, consumer_id, credential_id or consumer_id)
    s:save()
  end
end


function KongSessionHandler:access(conf)
  access.execute(conf)
end


return KongSessionHandler
