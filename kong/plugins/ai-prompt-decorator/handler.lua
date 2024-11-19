local ai_plugin_base = require("kong.llm.plugin.base")

local NAME = "ai-prompt-decorator"
local PRIORITY = 772

local AIPlugin = ai_plugin_base.define(NAME, PRIORITY)

AIPlugin:enable(AIPlugin.register_filter(require("kong.llm.plugin.shared-filters.parse-request")))
AIPlugin:enable(AIPlugin.register_filter(require("kong.plugins." .. NAME .. ".filters.decorate-prompt")))

return AIPlugin:as_kong_plugin()