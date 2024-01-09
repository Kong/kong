local _M = {}

-- imports
local kong_meta     = require "kong.meta"
local cjson         = require("cjson.safe")
local http          = require("resty.http")
local fmt           = string.format
local str_lower     = string.lower
local str_format    = string.format
local ngx_print     = ngx.print
local str_lower     = string.lower
local str_format    = string.format
local base64_encode = ngx.encode_base64

local llm = require("kong.llm")
--

_M.PRIORITY = 776
_M.VERSION = kong_meta.version

local function bad_request(msg)
  kong.log.warn(msg)
  return kong.response.exit(400, { error = true, message = msg })
end

local function internal_server_error(msg)
  kong.log.err(msg)
  return kong.response.exit(500, { error = true, message = msg })
end

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

local function subrequest(httpc, request_body, http_opts)
  httpc:set_timeouts(http_opts.http_timeout or 60000)

  local request_url = fmt("%s://%s:%d%s",
                          ngx.var.upstream_scheme,
                          ngx.ctx.balancer_data.host,
                          ngx.ctx.balancer_data.port,
                          ngx.var.upstream_uri
                        )

  local ok, err = httpc:connect {
    scheme = ngx.var.upstream_scheme,
    host = ngx.ctx.balancer_data.host,
    port = ngx.ctx.balancer_data.port,
    proxy_opts = http_opts.proxy_opts,
    ssl_verify = http_opts.ssl_verify or true,
  }

  if not ok then
    return nil, internal_server_error("failed to connect to upstream: " .. err)
  end

  local headers = kong.request.get_headers()
  headers["transfer-encoding"] = nil -- transfer-encoding is hop-by-hop, strip
                                     -- it out
  headers["content-length"] = nil -- clear content-length - it will be set
                                  -- later on by resty-http (if not found);
                                  -- further, if we leave it here it will
                                  -- cause issues if the value varies (if may
                                  -- happen, e.g., due to a different transfer
                                  -- encoding being used subsequently)

  if ngx.var.upstream_host == "" then
    headers["host"] = nil
  else
    headers["host"] = ngx.var.upstream_host
  end

  local res, err = httpc:request({
    method  = kong.request.get_method(),
    path    = ngx.var.upstream_uri,
    headers = headers,
    body    = request_body,
  })

  if not res then
    return nil, internal_server_error("subrequest failed: " .. err)
  end

  return res
end

local function create_http_opts(conf)
  local http_opts = {}

  if conf.http_proxy_host then -- port WILL be set via schema constraint
    if not http_opts.proxy_opts then http_opts.proxy_opts = {} end
    proxy_opts.http_proxy = fmt("http://%s:%d", conf.http_proxy_host, conf.http_proxy_port)
  end

  if conf.https_proxy_host then
    if not http_opts.proxy_opts then http_opts.proxy_opts = {} end
    proxy_opts.https_proxy = fmt("http://%s:%d", conf.https_proxy_host, conf.https_proxy_port)
  end
  
  http_opts.http_timeout = conf.http_timeout
  http_opts.ssl_verify = conf.ssl_verify

  return http_opts
end

function _M:access(conf)
  kong.service.request.enable_buffering()
  kong.ctx.shared.skip_response_transformer = true

  -- first find the configured LLM interface and driver
  local http_opts = create_http_opts(conf)
  local ai_driver, err = llm:new(conf.llm, http_opts)
  
  if not ai_driver then
    return internal_server_error(err)
  end

  kong.log.debug("intercepting plugin flow with one-shot request")
  local httpc = http.new()
  local res, err = subrequest(httpc, kong.request.get_raw_body(), http_opts)
  if err then
    return internal_server_error(err)
  end

  -- if asked, introspect the request before proxying
  kong.log.debug("introspecting response with LLM")
  local new_response_body, err = llm:ai_introspect_body(
    res:read_body(),
    conf.prompt,
    http_opts,
    conf.transformation_extract_pattern
  )

  if err then return bad_request(err) end

  if res.headers then res.headers["content-length"] = nil end
  local headers, body, status
  if conf.parse_llm_response_json_instructions then
    headers, body, status, err = llm:parse_json_instructions(new_response_body)
    if err then return internal_server_error(
      "failed to parse JSON response instructions from AI backend: " .. err)
    end

    for k, v in pairs(headers) do
      res.headers[k] = v  -- override e.g. ['content-type']
    end

    headers = res.headers
  else
    headers = res.headers     -- headers from upstream
    body = new_response_body  -- replacement body from AI
    status = res.status       -- status from upstream
  end

  return kong.response.exit(status, body, headers)

end


return _M
