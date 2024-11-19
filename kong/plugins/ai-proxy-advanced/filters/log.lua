-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local ai_plugin_ctx = require("kong.llm.plugin.ctx")
local get_balancer_instance = require("kong.plugins.ai-proxy-advanced.balancer").get_balancer_instance


local _M = {
  NAME = "ai-proxy-advanced-log",
  STAGE = "RES_POST_PROCESSING",
  DESCRIPTION = "collect necessary datat point for balancer",
}

function _M:run(conf)
  local target = ai_plugin_ctx.get_namespaced_ctx("ai-proxy-advanced-balance", "selected_target")
  if not target then
    return true
  end

  local balancer_instance, err = get_balancer_instance(conf)
  if not balancer_instance then
    return false, "failed to get balancer: " .. (err or "nil")
  end

  local _, err = balancer_instance:afterBalance(conf, target)

  if err then
    return kong.log.warn("failed to perform afterBalance operation: ", err)
  end

  return true
end

return _M