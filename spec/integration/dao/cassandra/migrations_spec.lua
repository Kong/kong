local DAO = require "kong.dao.cassandra.factory"
local cassandra = require "cassandra"
local Migrations = require "kong.tools.migrations"
local spec_helper = require "spec.spec_helpers"

--
-- Stubs, instanciation and custom assertions
--

local TEST_KEYSPACE = "kong_migrations_tests"
local PLUGIN_MIGRATIONS_STUB = require "spec.integration.dao.cassandra.fixtures.migrations.cassandra"
local CORE_MIGRATIONS_STUB = {
  {
    name = "stub_skeleton",
    init = true,
    up = function(options)
      return [[
        CREATE KEYSPACE IF NOT EXISTS "]]..options.keyspace..[["
          WITH REPLICATION = {'class' : 'SimpleStrategy', 'replication_factor' : 1};

        USE "]]..options.keyspace..[[";

        CREATE TABLE IF NOT EXISTS schema_migrations(
          id text PRIMARY KEY,
          migrations list<text>
        );
      ]]
    end,
    down = function(options)
      return [[
        DROP KEYSPACE "]]..options.keyspace..[[";
      ]]
    end
  },
  {
    name = "stub_mig1",
    up = function()
      return [[
        CREATE TABLE users(
          id uuid PRIMARY KEY,
          name text,
          age int
        );
      ]]
    end,
    down = function()
       return [[
         DROP TABLE users;
       ]]
    end
  },
  {
    name = "stub_mig2",
    up = function()
      return [[
        CREATE TABLE users2(
          id uuid PRIMARY KEY,
          name text,
          age int
        );
      ]]
    end,
    down = function()
       return [[
         DROP TABLE users2;
       ]]
    end
  }

}

local test_env = spec_helper.get_env() -- test environment
local test_configuration = test_env.configuration
local test_cassandra_properties = test_configuration.databases_available[test_configuration.database].properties
test_cassandra_properties.keyspace = TEST_KEYSPACE

local test_dao = DAO(test_cassandra_properties)
local session = cassandra:new()

local function has_table(state, arguments)
  local rows, err = session:execute("SELECT columnfamily_name FROM system.schema_columnfamilies WHERE keyspace_name = ?;",
                                   {TEST_KEYSPACE})
  if err then
    error(err)
  end

  local found = false
  for _, table in ipairs(rows) do
    if table.columnfamily_name == arguments[1] then
      return true
    end
  end

  return found
end

local say = require "say"
say:set("assertion.has_table.positive", "Expected keyspace to have table %s")
say:set("assertion.has_table.negative", "Expected keyspace not to have table %s")
assert:register("assertion", "has_table", has_table, "assertion.has_table.positive", "assertion.has_table.negative")

local function has_migration(state, arguments)
  local identifier = arguments[1]
  local migration = arguments[2]

  local rows, err = test_dao.migrations:get_migrations()
  if err then
    error(err)
  end

  for _, record in ipairs(rows) do
    if record.id == identifier then
      for _, migration_record in ipairs(record.migrations) do
        if migration_record == migration then
          return true
        end
      end
    end
  end

  return false
end

local say = require "say"
say:set("assertion.has_migration.positive", "Expected keyspace to have migration %s record")
say:set("assertion.has_migration.negative", "Expected keyspace not to have migration %s recorded")
assert:register("assertion", "has_migration", has_migration, "assertion.has_migration.positive", "assertion.has_migration.negative")

--
-- Migrations test suite
--

describe("Migrations", function()
  local migrations

  setup(function()
    local ok, err = session:connect(test_cassandra_properties.contact_points, test_cassandra_properties.port)
    if not ok then
      error(err)
    end
  end)

  teardown(function()
    local err = select(2, session:execute("DROP KEYSPACE "..TEST_KEYSPACE))
    if err then
      error(err)
    end
  end)

  it("should be instanciable", function()
    migrations = Migrations(test_dao, CORE_MIGRATIONS_STUB, "spec.integration.dao.cassandra")
    assert.truthy(migrations)
    assert.same(CORE_MIGRATIONS_STUB, migrations.core_migrations)
  end)

  describe("migrate", function()
    it("should run core migrations", function()
      local cb = function(identifier, migration) end
      local s = spy.new(cb)

      local err = migrations:migrate("core", s)
      assert.falsy(err)

      assert.spy(s).was_called(3)
      assert.spy(s).was_called_with("core", CORE_MIGRATIONS_STUB[1])
      assert.spy(s).was_called_with("core", CORE_MIGRATIONS_STUB[2])
      assert.spy(s).was_called_with("core", CORE_MIGRATIONS_STUB[3])

      assert.has_table("users2")
      assert.has_migration("core", "stub_mig2")
    end)
    it("should run plugins migrations", function()
      local cb = function(identifier, migration) end
      local s = spy.new(cb)

      local err = migrations:migrate("fixtures", s)
      assert.falsy(err)

      assert.spy(s).was_called(2)
      assert.spy(s).was_called_with("fixtures", PLUGIN_MIGRATIONS_STUB[1])
      assert.spy(s).was_called_with("fixtures", PLUGIN_MIGRATIONS_STUB[2])

      assert.has_table("plugins2")
      assert.has_migration("fixtures", "stub_fixture_mig2")
    end)
  end)
  describe("rollback", function()
    it("should rollback core migrations", function()
      local rollbacked, err = migrations:rollback("core")
      assert.falsy(err)
      assert.equal("stub_mig2", rollbacked.name)
      assert.not_has_migration("core", "stub_mig2")
      assert.not_has_table("users2")
      assert.has_migration("core", "stub_mig1")
      assert.has_table("users")
    end)
    it("should rollback plugins migrations", function()
      local rollbacked, err = migrations:rollback("fixtures")
      assert.falsy(err)
      assert.equal("stub_fixture_mig2", rollbacked.name)
      assert.not_has_migration("fixtures", "stub_fixture_mig2")
      assert.not_has_table("plugins2")
      assert.has_migration("fixtures", "stub_fixture_mig1")
      assert.has_table("plugins")
    end)
  end)
  describe("migrate bis", function()
    it("should migrate core from the last record", function()
      local cb = function(identifier, migration) end
      local s = spy.new(cb)

      local err = migrations:migrate("core", s)
      assert.falsy(err)

      assert.spy(s).was_called(1)
      assert.spy(s).was_called_with("core", CORE_MIGRATIONS_STUB[3])

      assert.has_table("users2")
      assert.has_migration("core", "stub_mig2")
    end)
    it("should migrate plugins from the last record", function()
      local cb = function(identifier, migration) end
      local s = spy.new(cb)

      local err = migrations:migrate("fixtures", s)
      assert.falsy(err)

      assert.spy(s).was_called(1)
      assert.spy(s).was_called_with("fixtures", PLUGIN_MIGRATIONS_STUB[2])

      assert.has_table("plugins2")
      assert.has_migration("fixtures", "stub_fixture_mig2")
    end)
  end)
end)
