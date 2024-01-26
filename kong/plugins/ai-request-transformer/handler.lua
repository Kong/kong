-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local _M = {}

-- imports
local kong_meta     = require "kong.meta"
local fmt           = string.format
local llm           = require("kong.llm")
--

_M.PRIORITY = 777
_M.VERSION = kong_meta.core_version

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

  if err then
    return bad_request(err)
  end
  
  -- set the body for later plugins
  kong.service.request.set_raw_body(new_request_body)

  -- continue into other plugins including ai-response-transformer,
  -- which may exit early with a sub-request
end


return _M
