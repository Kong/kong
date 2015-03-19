local path = require("path").new("/")
local utils = require "kong.tools.utils"
local Object = require "classic"

local KONG_HOME = os.getenv("KONG_HOME") and os.getenv("KONG_HOME") or "."
local MIGRATION_PATH = path:join(KONG_HOME, "database/migrations")

-- Migrations
local Migrations = Object:extend()

function Migrations:new(dao)
  self.dao = dao
  self.options = { keyspace = dao._properties.keyspace }
  self.migrations_files = utils.retrieve_files(path:join(MIGRATION_PATH, dao.type), '.lua')
  table.sort(self.migrations_files)
end

-- Createa migration interface for each database available
function Migrations.create(configuration, name, callback)
  for k, _ in pairs(configuration.databases_available) do
    local date_str = os.date("%Y-%m-%d-%H%M%S")
    local file_path = path:join(MIGRATION_PATH, k)
    local file_name = date_str.."_"..name
    local interface = [[
local Migration = {
  name = "]]..file_name..[[",

  up = function(options)
    return ]].."[["..[[


    ]].."]]"..[[

  end,

  down = function(options)
    return ]].."[["..[[


    ]].."]]"..[[

  end
}

return Migration
    ]]

    if callback then
      callback(interface, file_path, file_name, k)
    end
  end
end

-- Execute all migrations UP
-- @param callback A function to execute on each migration (ie: for logging)
function Migrations:migrate(callback)
  local old_migrations, err = self.dao:get_migrations()
  if err then
    callback(nil, err)
    return
  end

  -- Retrieve migrations to execute
  local diff_migrations = {}
  if old_migrations then
    -- Only execute from the latest executed migrations
    for i, migration in ipairs(self.migrations_files) do
      if old_migrations[i] == nil then
        table.insert(diff_migrations, migration)
      end
    end
    -- If no diff, there is no new migration to run
    if #diff_migrations == 0 then
      callback(nil, nil)
      return
    end
  else
    -- No previous migrations, just execute all migrations
    diff_migrations = self.migrations_files
  end

  -- Execute all new migrations, in order
  for _, file_path in ipairs(diff_migrations) do
    -- Load our migration script
    local migration = loadfile(file_path)()

    -- Generate UP query from string + options
    local up_query = migration.up(self.options)
    local err = self.dao:execute_queries(up_query, migration.init)
    if err then
      callback(nil, err)
      return
    end

    -- Record migration in db
    local _, err = self.dao:add_migration(migration.name)
    if err then
      err = "Cannot record migration "..migration.name..": "..err
    end

    callback(migration, err)
    if err then
      break
    end
  end
end

-- Take the latest executed migration and DOWN it
-- @param callback A function to execute (for consistency with other functions of this module)
function Migrations:rollback(callback)
  local old_migrations, err = self.dao:get_migrations()
  if err then
    callback(nil, err)
    return
  end

  local migration_to_rollback
  if old_migrations and #old_migrations > 0 then
    migration_to_rollback = loadfile(path:join(MIGRATION_PATH, self.dao.type, old_migrations[#old_migrations])..".lua")()
  else
    -- No more migration to rollback
    callback(nil, nil)
    return
  end

  -- Generate DOWN query from string + options
  local down_query = migration_to_rollback.down(self.options)
  local err = self.dao:execute_queries(down_query)
  if err then
    callback(nil, err)
    return
  end

  -- delete migration from schema changes records if it's not the first one
  -- (otherwise the schema_migrations table doesn't exist anymore)
  if not migration_to_rollback.init then
    local _, err = self.dao:delete_migration(migration_to_rollback.name)
    if err then
      callback(migration_to_rollback, "Cannot delete migration "..migration_to_rollback.name..": "..err)
      return
    end
  end

  callback(migration_to_rollback)
end

-- Execute all migrations DOWN
-- @param {function} callback A function to execute on each migration (ie: for logging)
function Migrations:reset(callback)
  local done = false
  while not done do
    self:rollback(function(migration, err)
      if not migration and not err then
        done = true
      end
      callback(migration, err)
    end)
  end
end

return Migrations
