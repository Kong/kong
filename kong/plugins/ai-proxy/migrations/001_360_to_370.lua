-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local ops = require("kong.db.migrations.operations.200_to_210")

local function update_logging_statistic(config)
  if config.logging.log_statistics and config.route_type == "llm/v1/completions"
    and config.model.provider == "anthropic" then
    config.logging.log_statistics = false
    return true
  end
end

return {
  postgres = {
    teardown = function(connector)
      ops.postgres.teardown:fixup_plugin_config(connector, "ai-proxy", update_logging_statistic)
    end
  }
}