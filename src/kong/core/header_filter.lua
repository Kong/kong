-- Copyright (C) Mashape, Inc.

local _M = {}

function _M.execute(conf)
  local api_time = ngx.ctx.proxy_end - ngx.ctx.proxy_start
  ngx.header["X-Kong-Proxy-Time"] = ngx.now() - ngx.ctx.start - api_time
  ngx.header["X-Kong-Api-Time"] = api_time
end

return _M
