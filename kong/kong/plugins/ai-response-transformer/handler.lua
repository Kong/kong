local ai_plugin_base = require("kong.llm.plugin.base")

local NAME = "ai-response-transformer"
local PRIORITY = 768

local AIPlugin = ai_plugin_base.define(NAME, PRIORITY)


local SHARED_FILTERS = {
  "enable-buffering",
}

for _, filter in ipairs(SHARED_FILTERS) do
  AIPlugin:enable(AIPlugin.register_filter(require("kong.llm.plugin.shared-filters." .. filter)))
end

AIPlugin:enable(AIPlugin.register_filter(require("kong.plugins.ai-response-transformer.filters.transform-response")))


return AIPlugin:as_kong_plugin()
