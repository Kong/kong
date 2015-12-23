local cassandra = require "cassandra"
local DAO = require "kong.dao.cassandra.factory"
local Migrations = require "kong.tools.migrations"
local spec_helper = require "spec.spec_helpers"

--
-- Fixtures, setup and custom assertions
--

local FIXTURES = {
  keyspace = "kong_migrations_tests",
  core_migrations_module = "spec.integration.dao.cassandra.fixtures.core_migrations",
  plugins_namespace = "spec.integration.dao.cassandra.fixtures",
  kong_config = {
    plugins_available = {"plugin_fixture"}
  }
}

local test_env = spec_helper.get_env() -- test environment
local test_configuration = test_env.configuration
local test_cassandra_properties = test_configuration.dao_config
test_cassandra_properties.keyspace = FIXTURES.keyspace

local test_dao = DAO(test_cassandra_properties)
local session, err = cassandra.spawn_session {
  shm = "factory_specs",
  contact_points = test_configuration.dao_config.contact_points
}
if err then
  error(err)
end

local function has_table(state, arguments)
  local rows, err = session:execute("SELECT columnfamily_name FROM system.schema_columnfamilies WHERE keyspace_name = ?", {FIXTURES.keyspace})
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

local function has_keyspace(state, arguments)
  local rows, err = session:execute("SELECT * FROM system.schema_keyspaces WHERE keyspace_name = ?", {arguments[1]})
  if err then
    error(err)
  end

  return #rows > 0
end

say:set("assertion.has_keyspace.positive", "Expected keyspace %s to exist")
say:set("assertion.has_keyspace.negative", "Expected keyspace %s to not exist")
assert:register("assertion", "has_keyspace", has_keyspace, "assertion.has_keyspace.positive", "assertion.has_keyspace.negative")

local function has_replication_options(state, arguments)
  local rows, err = session:execute("SELECT * FROM system.schema_keyspaces WHERE keyspace_name = ?", {arguments[1]})
  if err then
    error(err)
  end

  if #rows > 0 then
    local keyspace = rows[1]
    assert.equal("org.apache.cassandra.locator."..arguments[2], keyspace.strategy_class)
    assert.equal(arguments[3], keyspace.strategy_options)
    return true
  end
end

say:set("assertion.has_replication_options.positive", "Expected keyspace %s to have given replication options")
say:set("assertion.has_replication_options.negative", "Expected keyspace %s to not have given replication options")
assert:register("assertion", "has_replication_options", has_replication_options, "assertion.has_replication_options.positive", "assertion.has_replication_options.negative")

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

say:set("assertion.has_migration.positive", "Expected keyspace to have migration %s record")
say:set("assertion.has_migration.negative", "Expected keyspace not to have migration %s recorded")
assert:register("assertion", "has_migration", has_migration, "assertion.has_migration.positive", "assertion.has_migration.negative")

--
-- Migrations test suite
--

describe("Migrations", function()
  local migrations

  teardown(function()
    session:execute("DROP KEYSPACE "..FIXTURES.keyspace)
  end)

  it("should be instanciable", function()
    migrations = Migrations(test_dao, FIXTURES.kong_config, FIXTURES.core_migrations_module, FIXTURES.plugins_namespace)
    assert.truthy(migrations)
  end)

  describe("Migration up/down", function()
    local core_migrations, plugin_migrations

    setup(function()
      core_migrations = migrations.migrations.core
      plugin_migrations = migrations.migrations.plugin_fixture
    end)

    describe("run_migrations()", function()
      it("should run core migrations", function()
        local before = spy.new(function() end)
        local on_each_success = spy.new(function() end)

        local err = migrations:run_migrations("core", before, on_each_success)
        assert.falsy(err)

        assert.spy(before).was_called(1)
        assert.spy(before).was_called_with("core")

        assert.spy(on_each_success).was_called(3)
        assert.spy(on_each_success).was_called_with("core", core_migrations[1])
        assert.spy(on_each_success).was_called_with("core", core_migrations[2])
        assert.spy(on_each_success).was_called_with("core", core_migrations[3])

        assert.has_table("users1")
        assert.has_migration("core", "stub_mig1")
        assert.has_table("users2")
        assert.has_migration("core", "stub_mig2")
      end)
      it("should run plugins migrations", function()
        local before = spy.new(function() end)
        local on_each_success = spy.new(function() end)

        local err = migrations:run_migrations("plugin_fixture", before, on_each_success)
        assert.falsy(err)

        assert.spy(before).was_called(1)
        assert.spy(before).was_called_with("plugin_fixture")

        assert.spy(on_each_success).was_called(2)
        assert.spy(on_each_success).was_called_with("plugin_fixture", plugin_migrations[1])
        assert.spy(on_each_success).was_called_with("plugin_fixture", plugin_migrations[2])

        assert.has_migration("plugin_fixture", "stub_fixture_mig1")
        assert.has_table("plugins1")
        assert.has_migration("plugin_fixture", "stub_fixture_mig2")
        assert.has_table("plugins2")
      end)
      it("should not run any migrations if all have already been run for this identifier", function()
        local before = spy.new(function() end)
        local on_each_success = spy.new(function() end)

        local err = migrations:run_migrations("core", before, on_each_success)
        assert.falsy(err)

        assert.spy(before).was_called(0)
        assert.spy(on_each_success).was_called(0)
      end)
      it("should return an error when identifier does not have migrations", function()
        local err = migrations:run_migrations("foo")
        assert.truthy(err)
        assert.equal("No migrations registered for foo", err)
      end)
    end)
    describe("run_rollback()", function()
      it("should rollback core migrations", function()
        local before = spy.new(function() end)
        local on_success = spy.new(function() end)

        local err = migrations:run_rollback("core", before, on_success)
        assert.falsy(err)

        assert.spy(before).was_called(1)
        assert.spy(before).was_called_with("core")

        assert.spy(on_success).was_called(1)
        assert.spy(on_success).was_called_with("core", core_migrations[3])

        assert.not_has_migration("core", "stub_mig2")
        assert.not_has_table("users2")
        assert.has_migration("core", "stub_mig1")
        assert.has_table("users1")
      end)
      it("should rollback plugins migrations", function()
        local before = spy.new(function() end)
        local on_success = spy.new(function() end)

        local err = migrations:run_rollback("plugin_fixture", before, on_success)
        assert.falsy(err)

        assert.spy(before).was_called(1)
        assert.spy(before).was_called_with("plugin_fixture")

        assert.spy(on_success).was_called(1)
        assert.spy(on_success).was_called_with("plugin_fixture", plugin_migrations[2])
        assert.not_has_migration("plugin_fixture", "stub_fixture_mig2")
        assert.not_has_table("plugins2")
        assert.has_migration("plugin_fixture", "stub_fixture_mig1")
        assert.has_table("plugins1")
      end)
      it("should return an error when identifier does not have migrations", function()
        local err = migrations:run_rollback("foo")
        assert.truthy(err)
        assert.equal("No migrations registered for foo", err)
      end)
    end)
    describe("run_migrations() bis", function()
      it("should migrate core from the last migration", function()
        local before = spy.new(function() end)
        local on_each_success = spy.new(function() end)

        local err = migrations:run_migrations("core", before, on_each_success)
        assert.falsy(err)

        assert.spy(before).was_called(1)
        assert.spy(before).was_called_with("core")

        assert.spy(on_each_success).was_called(1)
        assert.spy(on_each_success).was_called_with("core", core_migrations[3])

        assert.has_table("users2")
        assert.has_migration("core", "stub_mig2")
      end)
      it("should migrate plugins from the last record", function()
        local before = spy.new(function() end)
        local on_each_success = spy.new(function() end)

        local err = migrations:run_migrations("plugin_fixture", before, on_each_success)
        assert.falsy(err)

        assert.spy(before).was_called(1)
        assert.spy(before).was_called_with("plugin_fixture")

        assert.spy(on_each_success).was_called(1)
        assert.spy(on_each_success).was_called_with("plugin_fixture", plugin_migrations[2])

        assert.has_migration("plugin_fixture", "stub_fixture_mig2")
        assert.has_table("plugins2")
      end)
    end)
  end)

  describe("run_all_migrations()", function()
    setup(function()
      session:execute("DROP KEYSPACE "..FIXTURES.keyspace)
    end)
    it("should run all migrations for all identifier", function()
      local before = spy.new(function() end)
      local on_each_success = spy.new(function() end)
      spy.on(migrations, "run_migrations")
      finally(function()
        migrations.run_migrations:revert()
      end)

      local err = migrations:run_all_migrations(before, on_each_success)
      assert.falsy(err)

      assert.spy(migrations.run_migrations).was_called(2) -- core + plugin
      assert.spy(before).was_called(2)
      assert.spy(on_each_success).was_called(5) -- 5 migrations total

      assert.has_table("users1")
      assert.has_migration("core", "stub_mig1")
      assert.has_table("users2")
      assert.has_migration("core", "stub_mig2")

      assert.has_migration("plugin_fixture", "stub_fixture_mig1")
      assert.has_table("plugins1")
      assert.has_migration("plugin_fixture", "stub_fixture_mig2")
      assert.has_table("plugins2")
    end)
    it("should not run anything if schema is up to date", function()
      local before = spy.new(function() end)
      local on_each_success = spy.new(function() end)
      spy.on(migrations, "run_migrations")
      finally(function()
        migrations.run_migrations:revert()
      end)

      local err = migrations:run_all_migrations(before, on_each_success)
      assert.falsy(err)

      assert.spy(migrations.run_migrations).was_called(2) -- called, but won't trigger
      assert.spy(before).was_not_called()
      assert.spy(on_each_success).was_not_called()
    end)
  end)

  describe("migrations with DML statements", function()
    setup(function()
      migrations = Migrations(test_dao, {plugins_available = {"plugin_fixture_dml_migrations"}}, FIXTURES.core_migrations_module, FIXTURES.plugins_namespace)
    end)
    it("should be able to execute migrations modifying the stored data", function()
      local err = migrations:run_migrations("plugin_fixture_dml_migrations")
      assert.falsy(err)

      assert.has_migration("plugin_fixture_dml_migrations", "stub_fixture_dml_migrations1")
      assert.has_migration("plugin_fixture_dml_migrations", "stub_fixture_dml_migrations2")
      assert.has_table("some_table")

      local _, err = session:set_keyspace(FIXTURES.keyspace)
      assert.falsy(err)

      local rows, err = session:execute("SELECT * FROM some_table")
      assert.falsy(err)
      assert.equal(2, #rows)
    end)
    it("should be able to rollback migrations with DML statements", function()
      local err = migrations:run_rollback("plugin_fixture_dml_migrations")
      assert.falsy(err)

      assert.not_has_migration("plugin_fixture_dml_migrations", "stub_fixture_dml_migrations2")
      assert.has_migration("plugin_fixture_dml_migrations", "stub_fixture_dml_migrations1")
      assert.has_table("some_table")

      local rows, err = session:execute("SELECT * FROM some_table")
      assert.falsy(err)
      assert.equal(0, #rows)
    end)
  end)
  describe("keyspace replication strategy", function()
    local KEYSPACE_NAME = "kong_replication_strategy_tests"

    setup(function()
      migrations = Migrations(test_dao, FIXTURES.kong_config)
      migrations.dao_properties.keyspace = KEYSPACE_NAME
    end)
    after_each(function()
      session:execute("DROP KEYSPACE "..KEYSPACE_NAME)
    end)
    it("should create a keyspace with SimpleStrategy by default", function()
      local err = migrations:run_migrations("core")
      assert.falsy(err)
      assert.has_keyspace(KEYSPACE_NAME)
      assert.has_replication_options(KEYSPACE_NAME, "SimpleStrategy", "{\"replication_factor\":\"1\"}")
    end)
    it("should catch an invalid replication strategy", function()
      migrations.dao_properties.replication_strategy = "foo"
      local err = migrations:run_migrations("core")
      assert.truthy(err)
      assert.equal('Error executing migration for "core": invalid replication_strategy class', err)
    end)
  end)
end)
