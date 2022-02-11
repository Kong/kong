-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local meta       = require "kong.meta"
local http       = require "resty.http"
local ee         = require "kong.enterprise_edition"
local base64     = require "ngx.base64"
local cert_utils = require "kong.enterprise_edition.cert_utils"

local kong                = kong
local ngx                 = ngx
local ERR                 = ngx.ERR
local log                 = ngx.log
local ngx_req_get_headers = ngx.req.get_headers
local ngx_req_set_header  = ngx.req.set_header
local ngx_req_get_method  = ngx.req.get_method
local ngx_req_read_body    = ngx.req.read_body
local ngx_req_get_body    = ngx.req.get_body_data
local ngx_now             = ngx.now
local ngx_print           = ngx.print
local str_lower           = string.lower
local str_format          = string.format


local _prefix_log = "[forward-proxy] "
local server_header = meta._SERVER_TOKENS


local ForwardProxyHandler = {
  PRIORITY = 50,
  VERSION = "1.1.0"
}


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

  local kong_global = require "kong.global"
  local PHASES = kong_global.phases
  local current_phase = ctx.KONG_PHASE
  ctx.KONG_PHASE = PHASES.log

  ee.handlers.log.after(ctx)

  ctx.KONG_PHASE = current_phase
end


-- Borrowed from Kong 0.34-1 kong/runloop/handler.lua module
local function simulate_access_before()
  local var = ngx.var
  local realip_remote_addr = var.realip_remote_addr

  local forwarded_proto
  local forwarded_host
  local forwarded_port
  local forwarded_for

  -- X-Forwarded-* Headers Parsing
  --
  -- We could use $proxy_add_x_forwarded_for, but it does not work properly
  -- with the realip module. The realip module overrides $remote_addr and it
  -- is okay for us to use it in case no X-Forwarded-For header was present.
  -- But in case it was given, we will append the $realip_remote_addr that
  -- contains the IP that was originally in $remote_addr before realip
  -- module overrode that (aka the client that connected us).

  local trusted_ip = kong.ip.is_trusted(realip_remote_addr)
  if trusted_ip then
    forwarded_proto = var.http_x_forwarded_proto or var.scheme
    forwarded_host  = var.http_x_forwarded_host  or var.host
    forwarded_port  = var.http_x_forwarded_port  or var.server_port

  else
    forwarded_proto = var.scheme
    forwarded_host  = var.host
    forwarded_port  = var.server_port
  end

  local http_x_forwarded_for = var.http_x_forwarded_for
  if http_x_forwarded_for then
    forwarded_for = http_x_forwarded_for .. ", " .. realip_remote_addr

  else
    forwarded_for = var.remote_addr
  end

  ngx_req_set_header("X-Real-IP", var.remote_addr)
  ngx_req_set_header("X-Forwarded-For", forwarded_for)
  ngx_req_set_header("X-Forwarded-Proto", forwarded_proto)
  ngx_req_set_header("X-Forwarded-Host", forwarded_host)
  ngx_req_set_header("X-Forwarded-Port", forwarded_port)
end


-- http://www.w3.org/Protocols/rfc2616/rfc2616-sec13.html#sec13.5.1
local HOP_BY_HOP_HEADERS = {
    ["connection"]          = true,
    ["keep-alive"]          = true,
    ["proxy-authenticate"]  = true,
    ["proxy-authorization"] = true,
    ["te"]                  = true,
    ["trailers"]            = true,
    ["transfer-encoding"]   = true,
    ["upgrade"]             = true,
    ["content-length"]      = true, -- Not strictly hop-by-hop, but Nginx will deal
                                    -- with this (may send chunked for example).
}


-- Originally lifted from lua-resty-http (where is is now deprecated,
-- encouraging users to roll their own).
local function send_proxied_response(response)
  if not response then
    log(ERR, "no response provided")
    return
  end

  kong.response.set_status(response.status)

  -- Set headers, filtering out hop-by-hop.
  for k, v in pairs(response.headers) do
    if not HOP_BY_HOP_HEADERS[str_lower(k)] then
      kong.response.set_header(k, v)
    end
  end

  local reader = response.body_reader

  repeat
    local chunk, ok, read_err, print_err

    chunk, read_err = reader()
    if read_err then
      log(ERR, read_err)
    end

    if chunk then
      ok, print_err = ngx_print(chunk)
      if not ok then
        log(ERR, print_err)
      end
    end

    if read_err or print_err then
      break
    end
  until not chunk
end


function ForwardProxyHandler:access(conf)

  -- connect to the proxy
  local httpc = http:new()

  local ctx = ngx.ctx
  local var = ngx.var

  simulate_access_before()
  simulate_access_after(ctx)

  local addr = ctx.balancer_address

  httpc:set_timeouts(addr.connect_timeout, addr.send_timeout, addr.read_timeout)

  local proxy_opts = {}

  if conf.http_proxy_host then
    proxy_opts.http_proxy =
      str_format("http://%s:%d", conf.http_proxy_host, conf.http_proxy_port)
  end

  if conf.https_proxy_host then
    proxy_opts.https_proxy =
      str_format("https://%s:%d", conf.https_proxy_host, conf.https_proxy_port)
  end

  local ssl_client_cert, ssl_client_priv_key, err
  if ctx.service.client_certificate then
    ssl_client_cert, ssl_client_priv_key, err = cert_utils.load_certificate(ctx.service.client_certificate.id)
    if not ssl_client_cert or not ssl_client_priv_key then
      return kong.response.exit(500, err)
    end
  end

  local ok, err = httpc:connect {
    scheme = var.upstream_scheme,
    host = addr.host,
    port = addr.port,
    proxy_opts = proxy_opts,
    ssl_verify = conf.https_verify,
    ssl_server_name = addr.host,
    ssl_client_cert = ssl_client_cert,
    ssl_client_priv_key = ssl_client_priv_key,
  }

  if not ok then
    log(ERR, _prefix_log, "failed to connect to proxy: ", err)
    return kong.response.exit(500)
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

  if var.upstream_host == "" then
    headers["Host"] = nil
  else
    headers["Host"] = var.upstream_host
  end

  if conf.auth_username ~= nil and conf.auth_password ~= nil then
    local auth_header = "Basic " .. base64.encode_base64url(conf.auth_username .. ":" .. conf.auth_password)
    headers["Proxy-Authorization"] = auth_header
  end

  res, err = httpc:request({
    method  = ngx_req_get_method(),
    path    = var.upstream_uri,
    headers = headers,
    body    = ngx_req_get_body(),
  })
  if not res then
    log(ERR, _prefix_log, "failed to send proxy request: ", err)
    return kong.response.exit(500)
  end

  local callback = function()
    ngx.header["Via"] = server_header

    send_proxied_response(res)

    local ok, err = httpc:set_keepalive()
    if ok ~= 1 then
      log(ERR, "could not keepalive connection: ", err)
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
