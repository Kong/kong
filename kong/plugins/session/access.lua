local singletons = require "kong.singletons"
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
    return s:destroy()
  end

  if s.data and not s.data.authenticated_consumer
     and not s.data.authenticated_credential
  then
    return
  end

  -- only save when data is available
  s:save()

  local cid = s.data.authenticated_consumer
  local credential = s.data.authenticated_credential

  local consumer_cache_key = singletons.dao.consumers:cache_key(cid)
  local consumer, err = singletons.cache:get(consumer_cache_key, nil,
                                             load_consumer, cid)
  
  -- destroy sessions with invalid consumer_id
  if not consumer then
    s:destroy()
  end

  if err then
    ngx.log(ngx.ERR, "Error loading consumer: ", err)
    return
  end  

  ngx.ctx.authenticated_credential = credential
  ngx.ctx.authenticated_consumer = consumer
end


return _M
