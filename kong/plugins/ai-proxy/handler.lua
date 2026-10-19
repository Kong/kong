local ai_plugin_base = require("kong.llm.plugin.base")

local NAME = "ai-proxy"
local PRIORITY = 770

local AIPlugin = ai_plugin_base.define(NAME, PRIORITY)

local SHARED_FILTERS = {
  "parse-request", "save-request-body", "normalize-request", "enable-buffering",
  "normalize-response-header", "parse-sse-chunk", "normalize-sse-chunk",
  "parse-json-response", "normalize-json-response",
  "serialize-analytics",
}

for _, filter in ipairs(SHARED_FILTERS) do
  AIPlugin:enable(AIPlugin.register_filter(require("kong.llm.plugin.shared-filters." .. filter)))
end

return AIPlugin:as_kong_plugin()
