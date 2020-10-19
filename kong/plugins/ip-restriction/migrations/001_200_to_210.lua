local operations = require "kong.db.migrations.operations.200_to_210"


local function ws_migration_teardown(ops)
  return function(connector)
    return ops:fixup_plugin_config(connector, "ip-restriction", function(config)
      config.allow = config.whitelist
      config.whitelist = nil
      config.deny = config.blacklist
      config.blacklist = nil
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
