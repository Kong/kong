-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local ai_plugin_base = require("kong.llm.plugin.base")

local NAME = "ai-semantic-cache"
local PRIORITY = 765 -- leave space for other response-interceptor AI plugins

local AIPlugin = ai_plugin_base.define(NAME, PRIORITY)


local SHARED_FILTERS = {
  "parse-request", "enable-buffering",
  "parse-sse-chunk",
  "parse-json-response",
}

for _, filter in ipairs(SHARED_FILTERS) do
  AIPlugin:enable(AIPlugin.register_filter(require("kong.llm.plugin.shared-filters." .. filter)))
end

-- make sure our own filters are executed after request parsers
-- still, because of the priority setting, if ai-proxy are enabled, this plugin runs after the proxy
local PLUGIN_FILTERS = {
  "search-cache",
  "response-cc-header",
  "serve-response",
  "store-cache",
  "serialize-analytics",
}

for _, filter in ipairs(PLUGIN_FILTERS) do
  AIPlugin:enable(AIPlugin.register_filter(require("kong.plugins.ai-semantic-cache.filters." .. filter)))
end

return AIPlugin:as_kong_plugin()
