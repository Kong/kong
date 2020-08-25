local operations = require "kong.db.migrations.operations.200_to_210"


local function ws_migration_teardown(ops)
  return function(connector)
    ops:fixup_plugin_config(connector, "canary", function(config)
      if config.hash == "whitelist" then
        config.hash = "allow"
      elseif config.hash == "blacklist" then
        config.hash = "deny"
      end
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
