-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local ai_plugin_base = require("kong.llm.plugin.base")

local NAME = "ai-proxy-advanced"
local PRIORITY = 770 -- same as ai-proxy

local AIPlugin = ai_plugin_base.define(NAME, PRIORITY)

-- make sure our own filters are executed prior to shared ai-proxy filters
local PLUGIN_FILTERS = {
  "setup",
  "balance",
  "log",
}

for _, filter in ipairs(PLUGIN_FILTERS) do
  AIPlugin:enable(AIPlugin.register_filter(require("kong.plugins.ai-proxy-advanced.filters." .. filter)))
end


local SHARED_FILTERS = {
  "parse-request", "normalize-request", "enable-buffering",
  "parse-sse-chunk", "normalize-sse-chunk",
  "parse-json-response", "normalize-json-response",
  "serialize-analytics",
}

for _, filter in ipairs(SHARED_FILTERS) do
  AIPlugin:enable(AIPlugin.register_filter(require("kong.llm.plugin.shared-filters." .. filter)))
end

AIPlugin:enable_balancer_retry()

return AIPlugin:as_kong_plugin()
