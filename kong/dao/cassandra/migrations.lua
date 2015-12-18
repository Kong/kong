local cassandra = require "cassandra"
local stringy = require "stringy"
local BaseDao = require "kong.dao.cassandra.base_dao"

local Migrations = BaseDao:extend()

function Migrations:new(properties)
  self._table = "schema_migrations"
  self.queries = {
    get_keyspace = [[
      SELECT * FROM system.schema_keyspaces WHERE keyspace_name = ?;
    ]],
    add_migration = [[
      UPDATE schema_migrations SET migrations = migrations + ? WHERE id = ?;
    ]],
    get_all_migrations = [[
      SELECT * FROM schema_migrations;
    ]],
    get_migrations = [[
      SELECT migrations FROM schema_migrations WHERE id = ?;
    ]],
    delete_migration = [[
      UPDATE schema_migrations SET migrations = migrations - ? WHERE id = ?;
    ]]
  }

  Migrations.super.new(self, properties)
end

function Migrations:keyspace_exists(keyspace)
  local rows, err = Migrations.super.execute(self, self.queries.get_keyspace, {self.properties.keyspace}, nil, "system")
  if err then
    return nil, err
  else
    return #rows > 0
  end
end

-- Log (add) given migration to schema_migrations table.
-- @param migration_name Name of the migration to log
-- @return query result
-- @return error if any
function Migrations:add_migration(migration_name, identifier)
  return Migrations.super.execute(self, self.queries.add_migration, {cassandra.list({migration_name}), identifier})
end

-- Return all logged migrations with a filter by identifier optionally. Check if keyspace exists before to avoid error during the first migration.
-- @param identifier Only return migrations for this identifier.
-- @return A list of previously executed migration (as strings)
-- @return error if any
function Migrations:get_migrations(identifier)
  local keyspace_exists, err = self:keyspace_exists()
  if err then
    return nil, err
  elseif not keyspace_exists then
    -- keyspace is not yet created, this is the first migration
    return nil
  end

  local rows, err
  if identifier ~= nil then
    rows, err = Migrations.super.execute(self, self.queries.get_migrations, {identifier})
  else
    rows, err = Migrations.super.execute(self, self.queries.get_all_migrations)
  end

  if err and stringy.find(err.message, "unconfigured columnfamily schema_migrations") ~= nil then
    return nil, "Missing mandatory column family \"schema_migrations\" in configured keyspace. Please consider running \"kong migrations reset\" to fix this."
  elseif err then
    return nil, err
  elseif rows and #rows > 0 then
    return identifier == nil and rows or rows[1].migrations
  end
end

-- Unlog (delete) given migration from the schema_migrations table.
-- @return query result
-- @return error if any
function Migrations:delete_migration(migration_name, identifier)
  return Migrations.super.execute(self, self.queries.delete_migration, {cassandra.list({migration_name}), identifier})
end

-- Drop the entire keyspace
-- @param `keyspace` Name of the keyspace to drop
-- @return query result
function Migrations:drop_keyspace(keyspace)
  return Migrations.super.execute(self, string.format("DROP keyspace \"%s\"", keyspace))
end

function Migrations:drop()
  -- never drop this
end

return {migrations = Migrations}
