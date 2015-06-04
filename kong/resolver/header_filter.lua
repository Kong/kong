local constants = require "kong.constants"

local _M = {}

function _M.execute(conf)
  local api_time = ngx.ctx.proxy_ended_at - ngx.ctx.proxy_started_at
  ngx.header[constants.HEADERS.PROXY_TIME] = ngx.now() * 1000 - ngx.ctx.started_at - api_time
  ngx.header[constants.HEADERS.API_TIME] = api_time
end

return _M
