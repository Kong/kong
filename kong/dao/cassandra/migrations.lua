local cassandra = require "cassandra"
local BaseDao = require "kong.dao.cassandra.base_dao"

local Migrations = BaseDao:extend()

function Migrations:new(properties)
  self._table = "schema_migrations"
  self.queries = {
    add_migration = [[
      UPDATE schema_migrations SET migrations = migrations + ? WHERE id = 'migrations';
    ]],
    get_keyspace = [[
      SELECT * FROM system.schema_keyspaces WHERE keyspace_name = ?;
    ]],
    get_migrations = [[
      SELECT migrations FROM schema_migrations WHERE id = 'migrations';
    ]],
    delete_migration = [[
      UPDATE schema_migrations SET migrations = migrations - ? WHERE id = 'migrations';
    ]]
  }

  Migrations.super.new(self, properties)
end

-- Log (add) given migration to schema_migrations table.
-- @param migration_name Name of the migration to log
-- @return query result
-- @return error if any
function Migrations:add_migration(migration_name)
  return Migrations.super._execute(self, self.queries.add_migration,
    { cassandra.list({ migration_name }) })
end

-- Return all logged migrations if any. Check if keyspace exists before to avoid error during the first migration.
-- @return A list of previously executed migration (as strings)
-- @return error if any
function Migrations:get_migrations()
  local rows, err

  rows, err = Migrations.super._execute(self, self.queries.get_keyspace,
    { self._properties.keyspace }, nil, "system")
  if err then
    return nil, err
  elseif #rows == 0 then
    -- keyspace is not yet created, this is the first migration
    return nil
  end

  rows, err = Migrations.super._execute(self, self.queries.get_migrations)
  if err then
    return nil, err
  elseif rows and #rows > 0 then
    return rows[1].migrations
  end
end

-- Unlog (delete) given migration from the schema_migrations table.
-- @return query result
-- @return error if any
function Migrations:delete_migration(migration_name)
  return Migrations.super._execute(self, self.queries.delete_migration,
    { cassandra.list({ migration_name }) })
end

function Migrations:drop()
  -- never drop this
end

return { migrations = Migrations }
