-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

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
