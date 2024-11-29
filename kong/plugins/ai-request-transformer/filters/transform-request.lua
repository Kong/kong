-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local fmt            = string.format
local ai_plugin_ctx  = require("kong.llm.plugin.ctx")
local ai_plugin_o11y = require("kong.llm.plugin.observability")
local ai_shared      = require("kong.llm.drivers.shared")
local llm            = require("kong.llm")


local _M = {
  NAME = "ai-request-transformer-transform-request",
  STAGE = "REQ_TRANSFORMATION",
  }

local FILTER_OUTPUT_SCHEMA = {
  transformed = "boolean",
  model = "table",
  -- TODO: refactor this so they don't need to be duplicated
  llm_prompt_tokens_count = "number",
  llm_completion_tokens_count = "number",
  llm_usage_cost = "number",
}

local _, set_ctx = ai_plugin_ctx.get_namespaced_accesors(_M.NAME, FILTER_OUTPUT_SCHEMA)

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



function _M:run(conf)
  -- get cloud identity SDK, if required
  local identity_interface = _KEYBASTION[conf.llm]

  if identity_interface and identity_interface.error then
    kong.log.err("error authenticating with ", conf.llm.model.provider, " using native provider auth, ", identity_interface.error)
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

  set_ctx("model", conf.llm.model)
  set_ctx("llm_prompt_tokens_count", ai_plugin_o11y.metrics_get("llm_prompt_tokens_count") or 0)
  set_ctx("llm_completion_tokens_count", ai_plugin_o11y.metrics_get("llm_completion_tokens_count") or 0)
  set_ctx("llm_usage_cost", ai_plugin_o11y.metrics_get("llm_usage_cost") or 0)

  -- set the body for later plugins
  kong.service.request.set_raw_body(new_request_body)

  set_ctx("transformed", true)
  return true
end


return _M
