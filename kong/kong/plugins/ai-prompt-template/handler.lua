
local ai_plugin_base = require("kong.llm.plugin.base")

local NAME = "ai-prompt-template"
local PRIORITY = 773

local AIPlugin = ai_plugin_base.define(NAME, PRIORITY)

AIPlugin:enable(AIPlugin.register_filter(require("kong.plugins." .. NAME .. ".filters.render-prompt-template")))

return AIPlugin:as_kong_plugin()