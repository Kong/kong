local operations = require "kong.db.migrations.operations.200_to_210"

local PLUGIN_NAME = "response-transformer-advanced"

local function ws_migration_teardown(ops)
  return function(connector)
    ops:fixup_plugin_config(connector, PLUGIN_NAME, function(config)
      config.allow = config.whitelist
      config.whitelist = nil
      return true
    end)
  end
end


return {
  postgres = {
    up = "",
    teardown = ws_migration_teardown(operations.postgres.teardown),
  },

  cassandra = {
    up = "",
    teardown = ws_migration_teardown(operations.cassandra.teardown),
  },
}
