local uri = require("kong.tools.uri")
local operations = require("kong.db.migrations.operations.200_to_210")


local function pg_routes_migration(connector)
  local arrays = require("pgmoon.arrays")

  for route, err in connector:iterate("SELECT id, paths FROM routes") do
    if err then
      return nil, err
    end

    local changed = false

    for i, p in ipairs(route.paths) do
      local normalized = uri.normalize(p, true)
      if normalized ~= p then
        changed = true
        route.paths[i] = normalized
      end
    end

    if changed then
      local sql = string.format("UPDATE routes SET paths = %s WHERE id = '%s'",
                                arrays.encode_array(route.paths), route.id)

      local _, err = connector:query(sql)
      if err then
        return nil, err
      end
    end
  end

  return true
end

local function c_routes_migration(coordinator)
  local cassandra = require "cassandra"
  for rows, err in coordinator:iterate("SELECT id, paths FROM routes") do
    if err then
      return nil, err
    end

    for i = 1, #rows do
      local route = rows[i]
      local changed = false

      for i, p in ipairs(route.paths) do
        local normalized = uri.normalize(p, true)
        if normalized ~= p then
          changed = true
          route.paths[i] = normalized
        end
      end

      if changed then
        for i, p in ipairs(route.paths) do
          route.paths[i] = cassandra.text(p)
        end

        local _, err = coordinator:execute(
          "UPDATE routes SET cert_digest = ? WHERE partition = 'routes' AND id = ?", {
            cassandra.list(route.paths),
            cassandra.uuid(route.id)
          }
        )
        if err then
          return nil, err
        end
      end
    end
  end

  return true
end

return {
  postgres = {
    teardown = function(connector)
      local _, err = pg_routes_migration(connector)
      if err then
        return nil, err
      end

      return true
    end,
  },
  cassandra = {
    teardown = function(connector)
      local coordinator = assert(connector:get_stored_connection())
      local default_ws, err = operations.cassandra_ensure_default_ws(coordinator)
      if err then
        return nil, err
      end

      if not default_ws then
        return nil, "unable to find a default workspace"
      end

      local _, err = c_routes_migration(coordinator)
      if err then
        return nil, err
      end

      return true
    end
  }
}
