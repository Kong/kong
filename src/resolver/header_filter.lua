local constants = require "kong.constants"

local _M = {}

function _M.execute(conf)
  local api_time = ngx.ctx.proxy_end - ngx.ctx.proxy_start
  ngx.header[constants.HEADERS.PROXY_TIME] = ngx.now() - ngx.ctx.start - api_time
  ngx.header[constants.HEADERS.API_TIME] = api_time
end

return _M
