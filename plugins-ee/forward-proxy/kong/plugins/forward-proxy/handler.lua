-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local http       = require "resty.http"
local cert_utils = require "kong.enterprise_edition.cert_utils"
local meta       = require "kong.meta"
local lfs        = require("lfs")

local kong                = kong
local ngx                 = ngx
local ERR                 = ngx.ERR
local WARN                = ngx.WARN
local DEBUG               = ngx.DEBUG
local log                 = ngx.log
local ngx_req_get_headers = ngx.req.get_headers
local ngx_req_set_header  = ngx.req.set_header
local ngx_req_get_method  = ngx.req.get_method
local ngx_req_read_body   = ngx.req.read_body
local ngx_req_get_body    = ngx.req.get_body_data
local ngx_now             = ngx.now
local ngx_print           = ngx.print
local str_lower           = string.lower
local str_format          = string.format
local str_find            = string.find
local str_sub             = string.sub
local base64_encode       = ngx.encode_base64


local _prefix_log = "[forward-proxy] "
local server_header = meta._SERVER_TOKENS
local _logged_proxy_config_warning


local ForwardProxyHandler = {
  PRIORITY = 50,
  VERSION = meta.core_version
}

local function parse_ngx_size(str)
  local scales = {
    k = 1024,
    K = 1024,
    m = 1024 * 1024,
    M = 1024 * 1024
  }
  local len = #str
  local unit = str_sub(str, len)
  local scale = scales[unit]
  if scale then
    len = len - 1
  else
    scale = 1
  end
  local size = tonumber(str_sub(str, 1, len)) or 0
  return size * scale
end

local DEFAULT_BUFFER_SIZE = parse_ngx_size("1m")
local MAX_BUFFER_SIZE = parse_ngx_size("64m")

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
end

-- Borrowed from Kong 0.34-1 kong/runloop/handler.lua module

-- mode should be one of "append", "transparent", "delete"
local function simulate_access_before(mode)
  local real_ip, forwarded_for, forwarded_proto, forwarded_host, forwarded_port
  local function finish_headers()
    ngx_req_set_header("X-Real-IP", real_ip)
    ngx_req_set_header("X-Forwarded-For", forwarded_for)
    ngx_req_set_header("X-Forwarded-Proto", forwarded_proto)
    ngx_req_set_header("X-Forwarded-Host", forwarded_host)
    ngx_req_set_header("X-Forwarded-Port", forwarded_port)
  end

  if mode == "delete" then
    return finish_headers() -- all set to nil
  end

  local var = ngx.var
  local realip_remote_addr = var.realip_remote_addr

  -- X-Forwarded-* Headers Parsing
  --
  -- We could use $proxy_add_x_forwarded_for, but it does not work properly
  -- with the realip module. The realip module overrides $remote_addr and it
  -- is okay for us to use it in case no X-Forwarded-For header was present.
  -- But in case it was given, we will append the $realip_remote_addr that
  -- contains the IP that was originally in $remote_addr before realip
  -- module overrode that (aka the client that connected us).

  local trusted_ip = kong.ip.is_trusted(realip_remote_addr)
  -- retrieve XFF header only if the ip is trusted, otherwise all set to nil
  if trusted_ip then
    real_ip = var.http_x_real_ip
    forwarded_proto = var.http_x_forwarded_proto
    forwarded_host  = var.http_x_forwarded_host
    forwarded_port  = var.http_x_forwarded_port
    forwarded_for = var.http_x_forwarded_for
  end

  -- we do not modify headers for transparent mode
  if mode == "transparent" then
    return finish_headers()
  end

  -- append (default) mode, we then update those headers

  -- we could get real ip from remote_addr by using ngx_http_realip_module,
  -- but to keep it simple, we just follow other headers' patterns
  real_ip = real_ip or var.remote_addr
  forwarded_proto = forwarded_proto or var.scheme
  forwarded_host  = forwarded_host or var.host
  forwarded_port  = forwarded_port or var.server_port
  if forwarded_for then
    forwarded_for = forwarded_for .. ", " .. realip_remote_addr
  else
    forwarded_for = realip_remote_addr
  end

  return finish_headers()
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
  local cached_headers = {}
  for k, v in pairs(response.headers) do
    if not HOP_BY_HOP_HEADERS[str_lower(k)] then
      cached_headers[k] = v
    end
  end
  kong.response.set_headers(cached_headers)

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


local function buffered_reader(file, total_size, buffer_size)
  buffer_size = buffer_size or DEFAULT_BUFFER_SIZE
  local readed = 0
  return function()
    local chunk = file:read(buffer_size)
    if chunk then
      readed = readed + #chunk
    end
    if chunk == nil and total_size ~= readed then
      return nil, "reading file error"
    end
    return chunk
  end
end


local function can_streaming_proxy(protocol, transfer_encoding)
  protocol = protocol or 0
  transfer_encoding = transfer_encoding or ""

  -- ngx.req.socket doesn't work at HTTP/2 and chunked encoding
  return not (protocol > 1.1
    or str_find(transfer_encoding, "chunked", nil, true))
end


local function nonstreaming_proxy(httpc, headers)
  log(DEBUG, _prefix_log, "forwarding request in a non-streaming manner")

  headers["content-length"] = nil -- clear content-length - it will be set
                                  -- later on by resty-http (if not found);
                                  -- further, if we leave it here it will
                                  -- cause issues if the value varies (if may
                                  -- happen, e.g., due to a different transfer
                                  -- encoding being used subsequently)

  headers["transfer-encoding"] = nil -- transfer-encoding is hop-by-hop, strip
                                     -- it out

  ngx_req_read_body()
  local body = ngx_req_get_body()
  local body_file, err
  if not body then
    local filename = ngx.req.get_body_file()
    if filename then
      body_file, err = io.open(filename, "r")
      if err then
        return nil, "failed to open file: " .. err
      end
      local size, err = lfs.attributes(filename, "size")
      if err then
        return nil, "faield to get filesize: " .. err
      end
      headers['Content-Length'] = size -- explicitly set the Content-Length for chunked proxy
      body = buffered_reader(body_file, size)
      log(WARN, _prefix_log, "Reading request body from a temporary file by using IO blocking APIs. "
        .. "Tuning nginx_http_client_body_buffer_size can avoid the request body being written to the filesystem "
        .. "to have better performance.")
    end
  end

  local res, err = httpc:request({
    method  = ngx_req_get_method(),
    path    = ngx.var.upstream_uri,
    headers = headers,
    body    = body,
  })

  if body_file then
    body_file:close()
  end

  return res, err
end

local function streaming_proxy(httpc, headers)
  log(DEBUG, _prefix_log, "forwarding request in a streaming manner")

  headers["transfer-encoding"] = nil -- transfer-encoding is hop-by-hop, strip
                                     -- it out

  local reader, err = httpc:get_client_body_reader()
  if err then
    return nil, err
  end

  return httpc:request({
    method  = ngx_req_get_method(),
    path    = ngx.var.upstream_uri,
    headers = headers,
    body    = reader,
  })
end

function ForwardProxyHandler:init_worker()
  local ngx_client_body_buffer_size = kong.configuration.nginx_http_client_body_buffer_size or 0
  local new_size = math.min(MAX_BUFFER_SIZE, math.max(DEFAULT_BUFFER_SIZE, parse_ngx_size(ngx_client_body_buffer_size)))
  if new_size ~= DEFAULT_BUFFER_SIZE then
    DEFAULT_BUFFER_SIZE = new_size
    local readable_size = new_size == MAX_BUFFER_SIZE and "64m" or ngx_client_body_buffer_size
    log(DEBUG, _prefix_log, str_format("file reading buffer size is adapted to %s based on nginx_http_client_body_buffer_size", readable_size))
  end
end

function ForwardProxyHandler:access(conf)

  -- connect to the proxy
  local httpc = http:new()

  local ctx = ngx.ctx
  local var = ngx.var

  simulate_access_before(conf.x_headers)
  simulate_access_after(ctx)

  local addr = ctx.balancer_data

  httpc:set_timeouts(addr.connect_timeout, addr.send_timeout, addr.read_timeout)

  local proxy_opts = {}

  local auth_header
  if conf.auth_username and conf.auth_password then
    auth_header = "Basic " .. base64_encode(conf.auth_username .. ":" .. conf.auth_password)

    proxy_opts.https_proxy_authorization = auth_header
    proxy_opts.http_proxy_authorization = auth_header
  end

  if conf.http_proxy_host then
    proxy_opts.http_proxy =
      str_format("http://%s:%d", conf.http_proxy_host, conf.http_proxy_port)
  else
    if not _logged_proxy_config_warning then
      kong.log.warn("`http_proxy_host` is not set and will fallback to `https_proxy_host`. ",
                    "Consider setting proxy host and port for both schemes to avoid unexpected behaviors")
      _logged_proxy_config_warning = true
    end

    proxy_opts.http_proxy =
      str_format("http://%s:%d", conf.https_proxy_host, conf.https_proxy_port)
  end

  if conf.https_proxy_host then
    -- lua-resty-http only support `http`
    proxy_opts.https_proxy =
      str_format("http://%s:%d", conf.https_proxy_host, conf.https_proxy_port)
  else
    if not _logged_proxy_config_warning then
      kong.log.warn("`https_proxy_host` is not set and will fallback to `http_proxy_host`. ",
                    "Consider setting proxy host and port for both schemes to avoid unexpected behaviors")
      _logged_proxy_config_warning = true
    end

    proxy_opts.https_proxy =
      str_format("http://%s:%d", conf.http_proxy_host, conf.http_proxy_port)
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

  local headers = ngx_req_get_headers()

  if var.upstream_host == "" then
    headers["host"] = nil
  else
    headers["host"] = var.upstream_host
  end

  local res, err
  if can_streaming_proxy(ngx.req.http_version(), headers["Transfer-Encoding"]) then
    res, err = streaming_proxy(httpc, headers)
  else
    res, err = nonstreaming_proxy(httpc, headers)
  end

  if not res then
    log(ERR, _prefix_log, "failed to send proxy request: ", err)
    return kong.response.exit(500)
  end

  -- When forward-proxy is not enabled, KONG_WAITING_TIME is calculated in header_filter phase
  -- When forward-proxy is enabled, the request for upstreams is sent in access phase,
  -- the ctx.KONG_WAITING_TIME should be calculated here followed by httpc:connect()
  ctx.KONG_WAITING_TIME = get_now() - ctx.KONG_ACCESS_ENDED_AT

  local callback = function()
    ngx.header["Via"] = server_header

    send_proxied_response(res)

    local ok, err = httpc:set_keepalive()
    if ok ~= 1 then
      log(ERR, "could not keepalive connection: ", err)
    end

    -- We should always exit the process with status 200 here
    -- It means this plugin finishes its task successfully and asks nginx to exit normally
    -- The real status code the client receives is setted in send_proxied_response
    return ngx.exit(200)
  end

  if ctx.delay_response and not ctx.delayed_response then
    ctx.delayed_response = {}
    ctx.delayed_response_callback = callback

    return
  end

  return callback()
end


return ForwardProxyHandler
