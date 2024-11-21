-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local ai_plugin_ctx = require("kong.llm.plugin.ctx")
local set_tried_target = require "kong.plugins.ai-proxy-advanced.balancer.state".set_tried_target
local get_balancer_instance = require("kong.plugins.ai-proxy-advanced.balancer").get_balancer_instance


local _M = {
  NAME = "ai-proxy-advanced-balance",
  STAGE = "REQ_TRANSFORMATION",
  DESCRIPTION = "run balancer",
}

local FILTER_OUTPUT_SCHEMA = {
  selected_target = "table",
}

local _, set_ctx = ai_plugin_ctx.get_namespaced_accesors(_M.NAME, FILTER_OUTPUT_SCHEMA)

local function bail(code, msg)
  if code == 400 and msg then
    kong.log.info(msg)
  end

  if ngx.get_phase() ~= "balancer" then
    return kong.response.exit(code, msg and { error = { message = msg } } or nil)
  end
end

function _M:run(conf)
  local balancer_instance, err = get_balancer_instance(conf)
  if not balancer_instance then
    kong.log.err("failed to get balancer: ", err)
    bail(500, "failed to get balancer" )
    return true
  end

  local selected, err = balancer_instance:getPeer()
  if err then
    kong.log.err("failed to get peer: ", err)
    bail(500, "failed to get peer")
    return true
  end

  if ngx.get_phase() == "access" then
    kong.service.set_retries(conf.balancer.retries)
    kong.service.set_timeouts(conf.balancer.connect_timeout, conf.balancer.write_timeout, conf.balancer.read_timeout)
  end

  -- pass along the top level magic keys to selected target/conf
  selected.__key__ = conf.__key__
  selected.__plugin_id = conf.__plugin_id
  selected.max_request_body_size = conf.max_request_body_size
  selected.response_streaming = conf.response_streaming
  selected.model_name_header = conf.model_name_header

  set_ctx("selected_target", selected)

  set_tried_target(selected)

  return true
end

return _M