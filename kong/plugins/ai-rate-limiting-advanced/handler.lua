-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local ai_plugin_base = require("kong.llm.plugin.base")

local NAME = "ai-rate-limiting-advanced"
local PRIORITY = 905

local AIPlugin = ai_plugin_base.define(NAME, PRIORITY)

local SHARED_FILTERS = {
  "parse-request",
}

for _, filter in ipairs(SHARED_FILTERS) do
  AIPlugin:enable(AIPlugin.register_filter(require("kong.llm.plugin.shared-filters." .. filter)))
end

local PLUGIN_FILTERS = {
  "setup",
  "limit-request", -- in access
  "increase-counter", -- in log phase
}

-- due to the fact that query cost (token count) is only known by the LLM service, the counter is
-- incremented in access phase like other RLA plugins. meaning there could be a slight lag between
-- the actual cost and the counter value.

for _, filter in ipairs(PLUGIN_FILTERS) do
  AIPlugin:enable(AIPlugin.register_filter(require("kong.plugins.ai-rate-limiting-advanced.filters." .. filter)))
end


return AIPlugin:as_kong_plugin()
