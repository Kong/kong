local operations = require "kong.db.migrations.operations.212_to_213"


local plugin_entities = {
  {
    name = "acls",
    primary_key = "id",
    uniques = {},
    cache_key = { "consumer", "group" },
    fks = {{name = "consumer", reference = "consumers", on_delete = "cascade"}},
  }
}

local function ws_migration_teardown(ops)
  return function(connector)
    local _, err = ops:ws_adjust_data(connector, plugin_entities)
    if err then
      return nil, err
    end

    return true
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
