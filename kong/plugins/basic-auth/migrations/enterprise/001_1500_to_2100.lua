local operations = require "kong.enterprise_edition.db.migrations.operations.1500_to_2100"


local plugin_entities = {
  {
    name = "basicauth_credentials",
    primary_key = "id",
    uniques = {"username"},
    fks = {{name = "consumer", reference = "consumers", on_delete = "cascade"}},
  }
}


--------------------------------------------------------------------------------
-- High-level description of the migrations to execute on 'teardown'
-- @param ops table: table of functions which execute the low-level operations
-- for the database (each function receives a connector).
-- @return a function that receives a connector
local function ws_migration_teardown(ops)
  return function(connector)
    ops:ws_adjust_data(connector, plugin_entities)
  end
end


--------------------------------------------------------------------------------


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
