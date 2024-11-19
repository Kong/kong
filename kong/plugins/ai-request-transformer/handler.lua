local ai_plugin_base = require("kong.llm.plugin.base")

local NAME = "ai-request-transformer"
local PRIORITY = 777

local AIPlugin = ai_plugin_base.define(NAME, PRIORITY)


local SHARED_FILTERS = {
  "enable-buffering",
}

for _, filter in ipairs(SHARED_FILTERS) do
  AIPlugin:enable(AIPlugin.register_filter(require("kong.llm.plugin.shared-filters." .. filter)))
end

AIPlugin:enable(AIPlugin.register_filter(require("kong.plugins.ai-request-transformer.filters.transform-request")))


return AIPlugin:as_kong_plugin()
