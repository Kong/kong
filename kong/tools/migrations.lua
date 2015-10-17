local utils = require "kong.tools.utils"
local Object = require "classic"
local fmt = string.format

local _CORE_MIGRATIONS_IDENTIFIER = "core"

local Migrations = Object:extend()

function Migrations:new(dao, kong_config, core_migrations_module, plugins_namespace)
  core_migrations_module = core_migrations_module or "kong.dao."..dao.type..".schema.migrations"
  plugins_namespace = plugins_namespace or "kong.plugins"

  -- Load the DAO which interacts with the migrations table
  dao:load_daos(require("kong.dao."..dao.type..".migrations"))

  self.dao = dao
  self.dao_properties = dao.properties
  self.migrations = {
    [_CORE_MIGRATIONS_IDENTIFIER] = require(core_migrations_module)
  }

  for _, plugin_identifier in ipairs(kong_config.plugins_available) do
    local has_migration, plugin_migrations = utils.load_module_if_exists(fmt("%s.%s.schema.migrations", plugins_namespace, plugin_identifier))
    if has_migration then
      self.migrations[plugin_identifier] = plugin_migrations
    end
  end
end

function Migrations:get_migrations(identifier)
  return self.dao.migrations:get_migrations(identifier)
end

function Migrations:run_all_migrations(before, on_each_success)
  local err = self:run_migrations(_CORE_MIGRATIONS_IDENTIFIER, before, on_each_success)
  if err then
    return err
  end

  for identifier in pairs(self.migrations) do
    -- skip core migrations
    if identifier ~= _CORE_MIGRATIONS_IDENTIFIER then
      local err = self:run_migrations(identifier, before, on_each_success)
      if err then
        return err
      end
    end
  end
end

--
-- PRIVATE
--

function Migrations:run_migrations(identifier, before, on_each_success)
  local migrations = self.migrations[identifier]
  if migrations == nil then
    return fmt("No migrations registered for %s", identifier)
  end

  -- Retrieve already executed migrations
  local old_migrations, err = self.dao.migrations:get_migrations(identifier)
  if err then
    return err
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
        return "Inconsistency"
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

  if before then
    before(identifier)
  end

  -- Execute all new migrations, in order
  for _, migration in ipairs(diff_migrations) do
    local err = migration.up(self.dao_properties, self.dao)
    if err then
      return fmt('Error executing migration for "%s": %s', identifier, err)
    end

    -- Record migration in db
    err = select(2, self.dao.migrations:add_migration(migration.name, identifier))
    if err then
      return fmt('Cannot record successful migration "%s" (%s): %s', migration.name, identifier, err)
    end

    -- Migration succeeded
    if on_each_success then
      on_each_success(identifier, migration)
    end
  end
end

function Migrations:run_rollback(identifier, before, on_success)
  local migrations = self.migrations[identifier]
  if migrations == nil then
    return fmt("No migrations registered for %s", identifier)
  end

  -- Retrieve already executed migrations
  local old_migrations, err = self.dao.migrations:get_migrations(identifier)
  if err then
    return err
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
      return fmt('Could not find migration "%s" to rollback it.', newest_migration_name)
    end
  else
    -- No more migration to rollback
    if on_success then
      on_success(identifier, nil) -- explicit no migration to rollback
    end
    return
  end

  if before then
    before(identifier)
  end

  local err = migration_to_rollback.down(self.dao_properties, self.dao)
  if err then
    return fmt('Error rollbacking migration for "%s": %s', identifier, err)
  end

  -- delete migration from schema changes records if it's not the first one
  -- (otherwise the schema_migrations table doesn't exist anymore)
  if not migration_to_rollback.init then
    err = select(2, self.dao.migrations:delete_migration(migration_to_rollback.name, identifier))
    if err then
      return fmt('Cannot record migration deletion "%s" (%s): %s', migration_to_rollback.name, identifier, err)
    end
  end

  if on_success then
    on_success(identifier, migration_to_rollback)
  end
end

return Migrations