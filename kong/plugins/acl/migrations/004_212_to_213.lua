-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

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
