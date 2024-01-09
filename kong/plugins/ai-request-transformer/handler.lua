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

_M.PRIORITY = 777
_M.VERSION = kong_meta.version

local function bad_request(msg)
  kong.log.warn(msg)
  return kong.response.exit(400, { error = true, message = msg })
end

local function internal_server_error(msg)
  kong.log.err(msg)
  return kong.response.exit(500, { error = true, message = msg })
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

  -- if asked, introspect the request before proxying
  kong.log.debug("introspecting request with LLM")
  local new_request_body, err = llm:ai_introspect_body(
    kong.request.get_raw_body(),
    conf.prompt,
    http_opts,
    conf.transformation_extract_pattern
  )

  if err then return bad_request(err) end

  -- only IF ai-response-transformer isn't enabled
  -- send upstream
  
  -- set the body for later plugins
  kong.service.request.set_raw_body(new_request_body)

  -- continue into other plugins including ai-response-transformer,
  -- which may exit early with a sub-request
end


return _M
