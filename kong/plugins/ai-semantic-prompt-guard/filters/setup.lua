-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local get_guard_instance = require("kong.plugins.ai-semantic-prompt-guard.guard").get_guard_instance
local delete_guard_instance = require("kong.plugins.ai-semantic-prompt-guard.guard").delete_guard_instance
local cleanup_by_configs = require("kong.plugins.ai-semantic-prompt-guard.guard").cleanup_by_configs
local crud_handler = require("kong.llm.plugin.crud_handler")

local BYPASS_CACHE = true

local _M = {
  NAME = "ai-semantic-prompt-guard-setup",
  STAGE = "SETUP",
  DESCRIPTION = "setup global state",
}

function _M:run(configs)
  if ngx.get_phase() ~= "init_worker" then -- configure phase
    -- configure phase
    cleanup_by_configs(configs)
    return true
  end

  -- init_worker phase
  crud_handler.new(function(data)
    local conf = data.entity.config

    local operation = data.operation
    if operation == "create" or operation == "update" then
      conf.__plugin_id = assert(data.entity.id, "missing plugin conf key __plugin_id")
      assert(get_guard_instance(conf, BYPASS_CACHE))

    elseif operation == "delete" then
      local conf_key = data.entity.id
      assert(conf_key, "missing plugin conf key data.entity.id")
      delete_guard_instance(conf_key)
    end
  end, "ai-semantic-prompt-guard", "managed_event")

  return true
end

return _M