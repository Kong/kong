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