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

  if s.data and not s.data.authenticated_consumer
     and not s.data.authenticated_credential
  then
    return s:destroy()
  end

  local c = s.data.authenticated_consumer
  local credential = s.data.authenticated_credential

  local consumer_cache_key = singletons.dao.consumers:cache_key(c.id)
  local consumer, err = singletons.cache:get(consumer_cache_key, nil,
                                             load_consumer, c.id)

  if err then
    return responses.send(err.status, err)
  end

  if not consumer then
    return s:destroy()
  end

  ngx.ctx.authenticated_credential = credential
  ngx.ctx.authenticated_consumer = consumer
end


return _M
