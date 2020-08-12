local operations = require "kong.db.migrations.operations.200_to_210"


local plugin_entities = {
  {
    name = "acls",
    primary_key = "id",
    uniques = {},
    fks = {{name = "consumer", reference = "consumers", on_delete = "cascade"}},
  }
}


local function ws_migration_up(ops)
  return ops:ws_adjust_fields(plugin_entities)
end


local function ws_migration_teardown(ops)
  return function(connector)
    ops:ws_adjust_data(connector, plugin_entities)
    ops:fixup_plugin_config(connector, "acl", function(config)
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
    up = ws_migration_up(operations.postgres.up),
    teardown = ws_migration_teardown(operations.postgres.teardown),
  },

  cassandra = {
    up = ws_migration_up(operations.cassandra.up),
    teardown = ws_migration_teardown(operations.cassandra.teardown),
  },
}
