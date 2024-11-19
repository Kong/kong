-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local event_hooks = require "kong.enterprise_edition.event_hooks"
local cleanup_by_configs = require "kong.plugins.ai-rate-limiting-advanced.namespaces".cleanup_by_configs

local _M = {
  NAME = "ai-rate-limiting-advanced-setup",
  STAGE = "SETUP",
  DESCRIPTION = "setup global state",
}


function _M:run(configs)
  if ngx.get_phase() ~= "init_worker" then -- configure phase
    cleanup_by_configs(configs)
    return true
  end

  -- init_worker phase
  event_hooks.publish("ai-rate-limiting-advanced", "rate-limit-exceeded", {
    fields = { "consumer", "ip", "service", "rate", "limit", "window" },
    unique = { "consumer", "ip", "service" },
    description = "Run an event when a rate limit has been exceeded",
  })
  return true
end

return _M