local BasePlugin = require "kong.plugins.base_plugin"
local meta       = require "kong.meta"
local http       = require "resty.http"
local ee         = require "kong.enterprise_edition"


local kong                = kong
local ngx                 = ngx
local ERR                 = ngx.ERR
local log                 = ngx.log
local ngx_req_get_headers = ngx.req.get_headers
local ngx_req_get_method  = ngx.req.get_method
local ngx_req_read_body    = ngx.req.read_body
local ngx_req_get_body    = ngx.req.get_body_data
local ngx_now             = ngx.now


local _prefix_log = "[forward-proxy] "
local server_header = meta._NAME .. "/" .. meta._VERSION


local ForwardProxyHandler = BasePlugin:extend()


ForwardProxyHandler.PRIORITY = 50
ForwardProxyHandler.VERSION = "0.0.5"


function ForwardProxyHandler:new()
  ForwardProxyHandler.super.new(self, "forward-proxy")
end


local function get_now()
  return ngx_now() * 1000 -- time is kept in seconds with millisecond resolution.
end


-- Plugins that generate content need to set latency headers and run
-- vitals methods. This function centralizes this cleanups so that
-- plugins can call it.
local function simulate_access_after(ctx)
  local var = ngx.var

  do
    -- Nginx's behavior when proxying a request with an empty querystring
    -- `/foo?` is to keep `$is_args` an empty string, hence effectively
    -- stripping the empty querystring.
    -- We overcome this behavior with our own logic, to preserve user
    -- desired semantics.
    local upstream_uri = var.upstream_uri

    if var.is_args == "?" or string.sub(var.request_uri, -1) == "?" then
      var.upstream_uri = upstream_uri .. "?" .. (var.args or "")
    end
  end

  local now = get_now()

  ctx.KONG_ACCESS_TIME = now - ctx.KONG_ACCESS_START
  ctx.KONG_ACCESS_ENDED_AT = now

  local proxy_latency = now - ngx.req.start_time() * 1000

  ctx.KONG_PROXY_LATENCY = proxy_latency

  ctx.KONG_PROXIED = true

  ee.handlers.access.after(ctx)
end


function ForwardProxyHandler:access(conf)
  ForwardProxyHandler.super.access(self)

  -- connect to the proxy
  local httpc = http:new()

  local ctx = ngx.ctx
  local var = ngx.var

  simulate_access_after(ctx)

  local addr = ctx.balancer_address

  httpc:set_timeout(addr.connect_timeout)

  local proxy_uri = "http://"  .. conf.proxy_host .. ":" .. conf.proxy_port .. "/"

  local ok, err = httpc:connect_proxy(proxy_uri, var.upstream_scheme,
                                      addr.host, addr.port)

  if not ok then
    log(ERR, _prefix_log, "failed to connect to proxy: ", err)
    return kong.response.exit(500)
  end

  if var.upstream_scheme == "https" then
    -- Perform the TLS handshake for HTTPS request.
    -- First param reuse_session set as `false` as session is not
    -- reused
    local ok, err = httpc:ssl_handshake(false, addr.host, conf.https_verify)
    if not ok then
      return kong.response.exit(500, err)
    end
  end

  local res
  local headers = ngx_req_get_headers()

  ngx_req_read_body()

  headers["transfer-encoding"] = nil -- transfer-encoding is hop-by-hop, strip
                                     -- it out

  headers["content-length"] = nil -- clear content-length - it will be set
                                  -- later on by resty-http (if not found);
                                  -- further, if we leave it here it will
                                  -- cause issues if the value varies (if may
                                  -- happen, e.g., due to a different transfer
                                  -- encoding being used subsequently)

  headers["Host"] = var.upstream_host

  local path

  if var.upstream_scheme == "https" and addr.port == 443 or
     var.upstream_scheme == "http" and addr.port == 80 then
    path = var.upstream_scheme .."://" .. addr.host .. var.upstream_uri

  else
    path = var.upstream_scheme .."://" .. addr.host .. ":" ..
           addr.port .. var.upstream_uri

    if var.upstream_host then
      headers["Host"] = var.upstream_host .. ":" .. addr.port
    end
  end

  res, err = httpc:request({
    method  = ngx_req_get_method(),
    path    = path,
    headers = headers,
    body    = ngx_req_get_body(),
  })
  if not res then
    log(ERR, _prefix_log, "failed to send proxy request: ", err)
    return kong.response.exit(500)
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
