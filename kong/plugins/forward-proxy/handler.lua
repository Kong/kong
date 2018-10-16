local BasePlugin = require "kong.plugins.base_plugin"
local responses  = require "kong.tools.responses"
local meta       = require "kong.meta"
local http       = require "resty.http"
local handler    = require "kong.core.handler"


local ngx                 = ngx
local ERR                 = ngx.ERR
local log                 = ngx.log
local ngx_req_get_headers = ngx.req.get_headers
local ngx_req_get_method  = ngx.req.get_method


local _prefix_log = "[forward-proxy] "
local server_header = meta._NAME .. "/" .. meta._VERSION


local ForwardProxyHandler = BasePlugin:extend()


ForwardProxyHandler.PRIORITY = 50
ForwardProxyHandler.VERSION = "0.0.3"


function ForwardProxyHandler:new()
  ForwardProxyHandler.super.new(self, "forward-proxy")
end


function ForwardProxyHandler:access(conf)
  ForwardProxyHandler.super.access(self)

  -- connect to the proxy
  local httpc = http:new()

  local ctx = ngx.ctx
  local var = ngx.var

  -- ... yep, this does exactly what you think it would
  handler.access.after(ctx)
  local addr = ctx.balancer_address

  httpc:set_timeout(addr.connect_timeout)

  local proxy_uri = "http://"  .. conf.proxy_host .. ":" .. conf.proxy_port .. "/"

  local ok, err = httpc:connect_proxy(proxy_uri, var.upstream_scheme,
                                      addr.host, addr.port)

  if not ok then
    log(ERR, _prefix_log, "failed to connect to proxy: ", err)
    return responses.send_HTTP_INTERNAL_SERVER_ERROR()
  end

  if var.upstream_scheme == "https" then
    -- Perform the TLS handshake for HTTPS request.
    -- First param reuse_session set as `false` as session is not
    -- reused
    local ok, err = httpc:ssl_handshake(false, addr.host, conf.https_verify)
    if not ok then
      return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
    end
  end

  local res
  local headers = ngx_req_get_headers()
  headers["Host"] = var.upstream_host
  res, err = httpc:request({
    method  = ngx_req_get_method(),
    path    = var.upstream_scheme .."://" .. addr.host .. var.upstream_uri,
    headers = headers,
    body    = httpc:get_client_body_reader(),
  })
  if not res then
    log(ERR, _prefix_log, "failed to send proxy request: ", err)
    return responses.send_HTTP_INTERNAL_SERVER_ERROR()
  end

  local callback = function()
    ngx.header["Via"] = server_header

    httpc:proxy_response(res)
    if var.upstream_scheme ~= "https" then
      -- Pooled SSL connection error out for next request, so connection
      -- is kept alive only for non HTTPS connections. A Github issue is
      -- created to track it https://github.com/pintsized/lua-resty-http/issues/161
      local ok, err = httpc:set_keepalive()
      if ok ~= 1 then
        log(ERR, "could not keepalive connection: ", err)
      end
    end

    return ngx.exit(res.status)
  end

  if ctx.delay_response and not ctx.delayed_response then
    ctx.delayed_response = {}
    ctx.delayed_response_callback = callback

    return
  end

  return callback()
end


return ForwardProxyHandler
