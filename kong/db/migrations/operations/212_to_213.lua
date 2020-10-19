-- Helper module for 200_to_210 migration operations.
--
-- Operations are versioned and specific to a migration so they remain
-- fixed in time and are not modified for use in future migrations.
--
-- If you want to reuse these operations in a future migration,
-- copy the functions over to a new versioned module.


local operations_200_210 = require "kong.db.migrations.operations.200_to_210"


--------------------------------------------------------------------------------
-- Postgres operations for Workspace migration
--------------------------------------------------------------------------------


local postgres = {

  up = [[
  ]],

  teardown = {
    -- These migrations were fixed since they were originally released,
    -- thus those that have updated already, need to re-run it.
    ws_update_composite_cache_key = operations_200_210.postgres.teardown.ws_update_composite_cache_key,
  },

}


--------------------------------------------------------------------------------
-- Cassandra operations for Workspace migration
--------------------------------------------------------------------------------


local cassandra = {

  up = [[
  ]],

  teardown = {
    -- These migrations were fixed since they were originally released,
    -- thus those that have updated already, need to re-run it.
    ws_update_composite_cache_key = operations_200_210.cassandra.teardown.ws_update_composite_cache_key,
  }

}


--------------------------------------------------------------------------------
-- Higher-level operations for Workspace migration
--------------------------------------------------------------------------------


local function ws_adjust_data(ops, connector, entities)
  for _, entity in ipairs(entities) do
    if entity.cache_key and #entity.cache_key > 1 then
      local _, err = ops:ws_update_composite_cache_key(connector, entity.name, entity.partitioned)
      if err then
        return nil, err
      end
    end
  end

  return true
end


postgres.teardown.ws_adjust_data = ws_adjust_data
cassandra.teardown.ws_adjust_data = ws_adjust_data


--------------------------------------------------------------------------------


return {
  postgres = postgres,
  cassandra = cassandra,
}
