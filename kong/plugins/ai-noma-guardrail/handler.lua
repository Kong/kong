-- +-------------------------------------------------------------+
--
--           Noma Security Guardrail Plugin for Kong
--                       https://noma.security
--
-- +-------------------------------------------------------------+

local ai_plugin_base = require("kong.llm.plugin.base")

local NAME = "ai-noma-guardrail"
local PRIORITY = 769  -- Between ai-response-transformer (768) and ai-proxy (770)

local AIPlugin = ai_plugin_base.define(NAME, PRIORITY)

-- Enable shared request parser
AIPlugin:enable(AIPlugin.register_filter(require("kong.llm.plugin.shared-filters.parse-request")))

AIPlugin:enable(AIPlugin.register_filter(require("kong.plugins." .. NAME .. ".filters.noma-guardrail")))

return AIPlugin:as_kong_plugin()
