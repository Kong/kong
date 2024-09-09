local _M = {}

-- imports
local kong_meta     = require "kong.meta"
local fmt           = string.format
local llm           = require("kong.llm")
local llm_state     = require("kong.llm.state")
local ai_shared     = require("kong.llm.drivers.shared")
--

_M.PRIORITY = 777
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
  llm_state.should_disable_ai_proxy_response_transform()

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

  -- if asked, introspect the request before proxying
  kong.log.debug("introspecting request with LLM")
  local new_request_body, err = ai_driver:ai_introspect_body(
    kong.request.get_raw_body(conf.max_request_body_size),
    conf.prompt,
    http_opts,
    conf.transformation_extract_pattern
  )

  if err then
    return bad_request(err)
  end

  -- set the body for later plugins
  kong.service.request.set_raw_body(new_request_body)

  -- continue into other plugins including ai-response-transformer,
  -- which may exit early with a sub-request
end


return _M
