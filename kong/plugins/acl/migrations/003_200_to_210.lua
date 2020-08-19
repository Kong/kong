local operations = require "kong.db.migrations.operations.200_to_210"


local plugin_entities = {
  {
    name = "acls",
    primary_key = "id",
    uniques = {},
    cache_key = { "consumer", "group" },
    fks = {{name = "consumer", reference = "consumers", on_delete = "cascade"}},
  }
}


local function ws_migration_up(ops)
  return ops:ws_adjust_fields(plugin_entities)
end


local function ws_migration_teardown(ops)
  return function(connector)
    local _, err = ops:ws_adjust_data(connector, plugin_entities)
    if err then
      return nil, err
    end

    _, err = ops:fixup_plugin_config(connector, "acl", function(config)
      config.allow = config.whitelist
      config.whitelist = nil
      config.deny = config.blacklist
      config.blacklist = nil
      return true
    end)
    if err then
      return nil, err
    end

    return true
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
