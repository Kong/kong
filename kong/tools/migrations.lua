local utils = require "kong.tools.utils"
local Object = require "classic"

local Migrations = Object:extend()

-- Instanciate a migrations runner.
-- @param `core_migrations` (Optional) If specified, will use those migrations for core instead of the real ones (for testing).
-- @param `plugins_namespace` (Optional) If specified, will look for plugins there instead of `kong.plugins` (for testing).
function Migrations:new(dao, core_migrations, plugins_namespace)
  dao:load_daos(require("kong.dao.cassandra.migrations"))

  if core_migrations then
    self.core_migrations = core_migrations
  else
    self.core_migrations = require("kong.dao."..dao.type..".schema.migrations")
  end

  self.dao = dao
  self.options = {keyspace = dao._properties.keyspace}
  self.plugins_namespace = plugins_namespace and plugins_namespace or "kong.plugins"
end

function Migrations:get_migrations(identifier)
  return self.dao.migrations:get_migrations(identifier)
end

function Migrations:migrate(identifier, callback)
  if identifier == "core" then
    return self:run_migrations(self.core_migrations, identifier, callback)
  else
    local has_migration, plugin_migrations = utils.load_module_if_exists(self.plugins_namespace.."."..identifier..".migrations."..self.dao.type)
    if has_migration then
      return self:run_migrations(plugin_migrations, identifier, callback)
    end
  end
end

function Migrations:rollback(identifier)
  if identifier == "core" then
    return self:run_rollback(self.core_migrations, identifier)
  else
    local has_migration, plugin_migrations = utils.load_module_if_exists(self.plugins_namespace.."."..identifier..".migrations."..self.dao.type)
    if has_migration then
      return self:run_rollback(plugin_migrations, identifier)
    end
  end
end

function Migrations:migrate_all(config, callback)
  local err = self:migrate("core", callback)
  if err then
    return err
  end

  for _, plugin_name in ipairs(config.plugins_available) do
    local err = self:migrate(plugin_name, callback)
    if err then
      return err
    end
  end
end

--
-- PRIVATE
--

function Migrations:run_migrations(migrations, identifier, callback)
  -- Retrieve already executed migrations
  local old_migrations, err = self.dao.migrations:get_migrations(identifier)
  if err then
    return nil, err
  end

  -- Determine which migrations have already been run
  -- and which ones need to be run.
  local diff_migrations = {}
  if old_migrations then
    -- Only execute from the latest executed migrations
    for i, migration in ipairs(migrations) do
      if old_migrations[i] == nil then
        table.insert(diff_migrations, migration)
      elseif old_migrations[i] ~= migration.name then
        return "Inconsitency"
      end
    end
    -- If no diff, there is no new migration to run
    if #diff_migrations == 0 then
      return
    end
  else
    -- No previous migrations, just execute all migrations
    diff_migrations = migrations
  end

  local err
  -- Execute all new migrations, in order
  for _, migration in ipairs(diff_migrations) do
    -- Generate UP query from string + options parameter
    local up_query = migration.up(self.options)
    err = self.dao:execute_queries(up_query, migration.init)
    if err then
      err = "Error executing migration for "..identifier..": "..err
      break
    end

    -- Record migration in db
    err = select(2, self.dao.migrations:add_migration(migration.name, identifier))
    if err then
      err = "Cannot record migration "..migration.name.." ("..identifier.."): "..err
      break
    end

    -- Migration succeeded
    if callback then
      callback(identifier, migration)
    end
  end

  return err
end

function Migrations:run_rollback(migrations, identifier)
  -- Retrieve already executed migrations
  local old_migrations, err = self.dao.migrations:get_migrations(identifier)
  if err then
    return nil, err
  end

  local migration_to_rollback
  if old_migrations and #old_migrations > 0 then
    -- We have some migrations to rollback
    local newest_migration_name = old_migrations[#old_migrations]
    for i = #migrations, 1, -1 do
      if migrations[i].name == newest_migration_name then
        migration_to_rollback = migrations[i]
        break
      end
    end
    if not migration_to_rollback then
      return nil, "Could not find migration \""..newest_migration_name.."\" to rollback it."
    end
  else
    -- No more migration to rollback
    return
  end

  -- Generate DOWN query from string + options
  local down_query = migration_to_rollback.down(self.options)
  local err = self.dao:execute_queries(down_query)
  if err then
    return nil, err
  end

  -- delete migration from schema changes records if it's not the first one
  -- (otherwise the schema_migrations table doesn't exist anymore)
  if not migration_to_rollback.init then
    local _, err = self.dao.migrations:delete_migration(migration_to_rollback.name, identifier)
    if err then
      return nil, "Cannot delete migration "..migration_to_rollback.name..": "..err
    end
  end

  return migration_to_rollback
end

return Migrations
