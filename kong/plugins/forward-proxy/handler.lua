local BasePlugin = require "kong.plugins.base_plugin"
local singletons = require "kong.singletons"
local responses  = require "kong.tools.responses"
local constants  = require "kong.constants"
local meta       = require "kong.meta"
local http       = require "resty.http"
local handler    = require "kong.runloop.handler"


local ngx                 = ngx
local ERR                 = ngx.ERR
local log                 = ngx.log
local ngx_req_get_headers = ngx.req.get_headers
local ngx_req_get_method  = ngx.req.get_method


local _prefix_log = "[forward-proxy] "
local server_header = meta._SERVER_TOKENS


local ForwardProxyHandler = BasePlugin:extend()


ForwardProxyHandler.PRIORITY = 50
ForwardProxyHandler.VERSION = "0.0.2"


function ForwardProxyHandler:new()
  ForwardProxyHandler.super.new(self, "forward-proxy")
end


function ForwardProxyHandler:access(conf)
  -- connect to the proxy
  local httpc = http:new()

  local ctx = ngx.ctx
  local api = ctx.api
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
  handler.access.after(ctx)

  local res, err = httpc:request({
    method  = ngx_req_get_method(),
    path    = "http://" .. var.upstream_host .. var.upstream_uri,
    headers = ngx_req_get_headers(),
    body    = httpc:get_client_body_reader(),
  })

  if not res then
    log(ERR, _prefix_log, "failed to send proxy request: ", err)
    return responses.send_HTTP_INTERNAL_SERVER_ERROR()
  end

  local callback = function()
    if singletons.configuration.enabled_headers[constants.HEADERS.VIA] then
      ngx.header[constants.HEADERS.VIA] = server_header
    end

    httpc:proxy_response(res)
    httpc:set_keepalive()

    return ngx.exit(res.status)
  end

  local ctx = ngx.ctx
  if ctx.delay_response and not ctx.delayed_response then
    ctx.delayed_response = {}
    ctx.delayed_response_callback = callback

    return
  end

  return callback()
end


return ForwardProxyHandler
