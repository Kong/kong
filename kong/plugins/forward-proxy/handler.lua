local BasePlugin = require "kong.plugins.base_plugin"
local responses  = require "kong.tools.responses"
local http       = require "resty.http"
local handler    = require "kong.core.handler"


local find                = string.find
local ERR                 = ngx.ERR
local log                 = ngx.log
local ngx_req_get_headers = ngx.req.get_headers
local ngx_req_get_method  = ngx.req.get_method
local unpack              = unpack


local _prefix_log = "[forward-proxy] "


local ForwardProxyHandler = BasePlugin:extend()


ForwardProxyHandler.PRIORITY = 50


function ForwardProxyHandler:new()
  ForwardProxyHandler.super.new(self, "forward-proxy")
end


function ForwardProxyHandler:access(conf)
  -- connect to the proxy
  local httpc = http:new()

  local api = ngx.ctx.api
  local var = ngx.var

  -- make the initial TCP connection
  -- TODO upgrade lua-resty-http to at least 0.10 to support
  -- set_timeouts
  httpc:set_timeout(api.upstream_connect_timeout)

  local ok, err = httpc:connect(conf.proxy_host, conf.proxy_port)
  if not ok then
    log(ERR, _prefix_log, "failed to connect to proxy: ", err)
    return responses.send_HTTP_INTERNAL_SERVER_ERROR()
  end

  -- ... yep, this does exactly what you think it would
  handler.access.after(ngx.ctx)

  local res, err = httpc:request({
    method  = ngx_req_get_method(),
    path    = "http://" .. ngx.var.upstream_host .. ngx.var.upstream_uri,
    headers = ngx_req_get_headers(),
    body    = httpc:get_client_body_reader(),
  })
  if not res then
    log(ERR, _prefix_log, "failed to send proxy request: ", err)
    return responses.send_HTTP_INTERNAL_SERVER_ERROR()
  end

  -- transparently send it back. note we will end up falling through kong's
  -- header filter, so X-Kong-* headers will be applied as expected
  httpc:proxy_response(res)
  return ngx.exit(res.status)
end


return ForwardProxyHandler
