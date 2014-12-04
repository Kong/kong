-- Copyright (C) Mashape, Inc.

local _M = {}

function _M.execute()
  ngx.log(ngx.DEBUG, "Base Header Filter")

  local api_time = ngx.ctx.proxy_end - ngx.ctx.proxy_start
  ngx.header["X-Apenode-Proxy-Time"] = ngx.now() - ngx.ctx.start - api_time
  ngx.header["X-Apenode-Api-Time"] = api_time

end

return _M
