local _M = {}

-- imports
local kong_meta     = require "kong.meta"
local http          = require("resty.http")
local fmt           = string.format
local kong_utils    = require("kong.tools.gzip")
local llm           = require("kong.llm")
local llm_state     = require("kong.llm.state")
local ai_shared     = require("kong.llm.drivers.shared")
--

_M.PRIORITY = 769
_M.VERSION = kong_meta.version

local _KEYBASTION = setmetatable({}, {
  __mode = "k",
  __index = ai_shared.cloud_identity_function,
})

local function bad_request(msg)
  kong.log.info(msg)
  return kong.response.exit(400, { error = { message = msg } })
end

local function internal_server_error(msg)
  kong.log.err(msg)
  return kong.response.exit(500, { error = { message = msg } })
end



local function subrequest(httpc, request_body, http_opts)
  httpc:set_timeouts(http_opts.http_timeout or 60000)

  local upstream_uri = ngx.var.upstream_uri
  if ngx.var.is_args == "?" or string.sub(ngx.var.request_uri, -1) == "?" then
    ngx.var.upstream_uri = upstream_uri .. "?" .. (ngx.var.args or "")
  end

  local ok, err = httpc:connect {
    scheme = ngx.var.upstream_scheme,
    host = ngx.ctx.balancer_data.host,
    port = ngx.ctx.balancer_data.port,
    proxy_opts = http_opts.proxy_opts,
    ssl_verify = http_opts.https_verify,
    ssl_server_name = ngx.ctx.balancer_data.host,
  }

  if not ok then
    return nil, "failed to connect to upstream: " .. err
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
    return nil, "subrequest failed: " .. err
  end

  return res
end



local function create_http_opts(conf)
  local http_opts = {}

  if conf.http_proxy_host then -- port WILL be set via schema constraint
    http_opts.proxy_opts = http_opts.proxy_opts or {}
    http_opts.proxy_opts.http_proxy = fmt("http://%s:%d", conf.http_proxy_host, conf.http_proxy_port)
  end

  if conf.https_proxy_host then
    http_opts.proxy_opts = http_opts.proxy_opts or {}
    http_opts.proxy_opts.https_proxy = fmt("http://%s:%d", conf.https_proxy_host, conf.https_proxy_port)
  end

  http_opts.http_timeout = conf.http_timeout
  http_opts.https_verify = conf.https_verify

  return http_opts
end



function _M:access(conf)
  llm_state.set_request_model(conf.llm.model and conf.llm.model.name)
  local kong_ctx_shared = kong.ctx.shared

  kong.service.request.enable_buffering()
  llm_state.disable_ai_proxy_response_transform()

  -- get cloud identity SDK, if required
  local identity_interface = _KEYBASTION[conf.llm]

  if identity_interface and identity_interface.error then
    kong_ctx_shared.skip_response_transformer = true
    kong.log.err("error authenticating with ", conf.model.provider, " using native provider auth, ", identity_interface.error)
    return kong.response.exit(500, "LLM request failed before proxying")
  end

  -- first find the configured LLM interface and driver
  local http_opts = create_http_opts(conf)
  conf.llm.__plugin_id = conf.__plugin_id
  conf.llm.__key__ = conf.__key__
  local ai_driver, err = llm.new_driver(conf.llm, http_opts, identity_interface)

  if not ai_driver then
    return internal_server_error(err)
  end

  kong.log.debug("intercepting plugin flow with one-shot request")
  local httpc = http.new()
  local res, err = subrequest(httpc,
    kong.request.get_raw_body(conf.max_request_body_size),
    http_opts)
  if err then
    return internal_server_error(err)
  end

  local res_body = res:read_body()
  local is_gzip = res.headers["Content-Encoding"] == "gzip"
  if is_gzip then
    res_body = kong_utils.inflate_gzip(res_body)
  end

  llm_state.set_parsed_response(res_body) -- future use

  -- if asked, introspect the request before proxying
  kong.log.debug("introspecting response with LLM")

  local new_response_body, err = ai_driver:ai_introspect_body(
    res_body,
    conf.prompt,
    http_opts,
    conf.transformation_extract_pattern
  )

  if err then
    return bad_request(err)
  end

  if res.headers then
    res.headers["content-length"] = nil
    res.headers["content-encoding"] = nil
    res.headers["transfer-encoding"] = nil
  end

  local headers, body, status
  if conf.parse_llm_response_json_instructions then
    headers, body, status, err = ai_driver:parse_json_instructions(new_response_body)
    if err then
      return internal_server_error("failed to parse JSON response instructions from AI backend: " .. err)
    end

    if headers then
      for k, v in pairs(headers) do
        res.headers[k] = v  -- override e.g. ['content-type']
      end
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
