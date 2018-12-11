local singletons = require "kong.singletons"
local responses = require "kong.tools.responses"
local session = require "kong.plugins.session.session"

local _M = {}


local function load_consumer(consumer_id)
  local result, err = singletons.dao.consumers:find { id = consumer_id }
  if not result then
    return nil, err
  end
  return result
end


function _M.execute(conf)
  local s = session.open_session(conf)

  if not s.present then
    return
  end

  -- check if incoming request is trying to logout
  if session.logout(conf) then
    s:destroy()
    return responses.send_HTTP_OK()
  end

  
  local cid = s.data.authenticated_consumer
  local credential = s.data.authenticated_credential
  
  local consumer_cache_key = singletons.dao.consumers:cache_key(cid)
  local consumer, err = singletons.cache:get(consumer_cache_key, nil,
                                             load_consumer, cid)
  
  if err then
    ngx.log(ngx.ERR, "Error loading consumer: ", err)
    return
  end
  
  -- destroy sessions with invalid consumer_id
  if not consumer then
    return s:destroy()
  end
  
  s:start()
  
  ngx.ctx.authenticated_credential = { id = credential or cid, consumer_id = cid }
  ngx.ctx.authenticated_consumer = consumer
  ngx.ctx.authenticated_session = s
end


return _M
