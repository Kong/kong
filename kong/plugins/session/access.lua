local session = require "resty.session"
local responses = require "kong.tools.responses"


local _M = {}


function open_session(conf)
  local session = session.open {
    name = conf.cookie_name or "session",
    random = { length = 32 },
    cookie = {
      lifetime = conf.cookie_lifetime,
      path     = conf.cookie_path,
      domain   = conf.cookie_domain,
      samesite = conf.cookie_samesite,
      httponly = conf.cookie_httponly,
      secure   = conf.cookie_secure
    },
  }
  if session.present then
    return session
  end

  if not session.started then
    session:start()
  end

  session:save()
  
  return session
end


-- TODO: retrieve consumer and credential
function verify_cookie(session)
  return {
    credential = { id = session.expires },
    consumer = { id = session.data.consumer_id }
  }
end


function _M.execute(conf)
  -- TODO: do real error handling
  local session, err = open_session(conf)
  local cookie = verify_cookie(session)

  if err then
    return responses.send(err.status, err.message)
  end

  ngx.ctx.authenticated_credential = cookie.credential.id
  ngx.ctx.authenticated_consumer = cookie.consumer.id
end


return _M
