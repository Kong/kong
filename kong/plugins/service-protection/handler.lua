-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]
local ratelimiting = require("kong.tools.public.rate-limiting").new_instance("service-protection", { redis_config_version = "v2" })
local schema = require "kong.plugins.service-protection.schema"
local event_hooks = require "kong.enterprise_edition.event_hooks"
local meta = require "kong.meta"
local handler_helper = require "kong.enterprise_edition.rl_plugin_helpers"

local kong = kong

local PLUGIN_NAME = "service-protection"

local SPHandler = {
  PRIORITY = 915,
  VERSION = meta.core_version
}


function SPHandler:init_worker()
  event_hooks.publish(PLUGIN_NAME, "rate-limit-exceeded", {
    fields = { "service", "rate", "limit", "window" },
    unique = { "service" },
    description = "Run an event when a rate limit has been exceeded",
  })
end


function SPHandler:configure(configs)
  handler_helper.configure_helper(configs, ratelimiting, schema, PLUGIN_NAME)
end


function SPHandler:access(conf)
  local key_id = kong.router.get_service() and kong.router.get_service().id
  return handler_helper.access_helper(conf, key_id, ratelimiting, schema, PLUGIN_NAME)
end


return SPHandler
