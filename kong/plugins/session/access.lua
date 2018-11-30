local responses = require "kong.tools.responses"
local session = require "kong.plugins.session.session"

local _M = {}


function _M.execute(conf)
  -- TODO: do real error handling
  local session, err = session.open_session(conf)

  if session.data and not session.data.authenticated_consumer then
    return
  end
  
  if err then
    return responses.send(err.status, err.message)
  end

  ngx.ctx.authenticated_credential = session.data.authenticated_credential
  ngx.ctx.authenticated_consumer = session.data.authenticated_consumer
end


return _M
