-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local get_balancer_instance = require("kong.plugins.ai-proxy-advanced.balancer").get_balancer_instance
local delete_balancer_instance = require("kong.plugins.ai-proxy-advanced.balancer").delete_balancer_instance
local cleanup_by_configs = require("kong.plugins.ai-proxy-advanced.balancer").cleanup_by_configs
local crud_handler = require("kong.llm.plugin.crud_handler")

local _M = {
  NAME = "ai-proxy-advanced-setup",
  STAGE = "SETUP",
  DESCRIPTION = "setup global state",
}

local BYPASS_CACHE = true


function _M:run(configs)
  if ngx.get_phase() ~= "init_worker" then -- configure phase
    cleanup_by_configs(configs)

    return true
  end

  -- init_worker phase

  crud_handler.new(function(data)
    local conf = data.entity.config

    local operation = data.operation
    if operation == "create" or operation == "update" then
      conf.__plugin_id = assert(data.entity.id, "missing plugin conf key __plugin_id")
      assert(get_balancer_instance(conf, BYPASS_CACHE))

    elseif operation == "delete" then
      local conf_key = data.entity.id
      assert(conf_key, "missing plugin conf key data.entity.id")
      delete_balancer_instance(conf_key)
    end
  end, "ai-proxy-advanced", "managed_event")

  return true
end

return _M