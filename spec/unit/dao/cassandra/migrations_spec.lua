local stringy = require "stringy"
local spec_helper = require "spec.spec_helpers"
local migrations = require "kong.dao.cassandra.schema.migrations"
local first_migration = migrations[1]

local migrations_stub = {
  execute_queries = function(self, queries)
    return queries
  end
}

local function strip_query(str)
  str = stringy.split(str, ";")[1]
  str = str:gsub("\n", " "):gsub("%s+", " ")
  return stringy.strip(str)
end

local test_config = spec_helper.get_env().configuration
local dao_config = test_config.dao_config
dao_config.keyspace = "kong"

describe("Cassandra migrations", function()
  describe("Keyspace options", function()
    it("should default to SimpleStrategy class with replication_factor of 1", function()
      local queries = first_migration.up(dao_config, migrations_stub)
      local keyspace_query = strip_query(queries)
      assert.equal("CREATE KEYSPACE IF NOT EXISTS \"kong\" WITH REPLICATION = {'class': 'SimpleStrategy', 'replication_factor': 1}", keyspace_query)
    end)
    it("should be possible to set a custom replication_factor", function()
      dao_config.replication_factor = 2
      local queries = first_migration.up(dao_config, migrations_stub)
      local keyspace_query = strip_query(queries)
      assert.equal("CREATE KEYSPACE IF NOT EXISTS \"kong\" WITH REPLICATION = {'class': 'SimpleStrategy', 'replication_factor': 2}", keyspace_query)
    end)
    it("should accept NetworkTopologyStrategy", function()
      dao_config.replication_strategy = "NetworkTopologyStrategy"
      local queries = first_migration.up(dao_config, migrations_stub)
      local keyspace_query = strip_query(queries)
      assert.equal("CREATE KEYSPACE IF NOT EXISTS \"kong\" WITH REPLICATION = {'class': 'NetworkTopologyStrategy'}", keyspace_query)
    end)
    it("should be possible to set data centers for NetworkTopologyStrategy", function()
      dao_config.data_centers = {
        dc1 = 2,
        dc2 = 3
      }
      local queries = first_migration.up(dao_config, migrations_stub)
      local keyspace_query = strip_query(queries)
      assert.equal("CREATE KEYSPACE IF NOT EXISTS \"kong\" WITH REPLICATION = {'class': 'NetworkTopologyStrategy', 'dc1': 2, 'dc2': 3}", keyspace_query)
    end)
    it("should return an error if an invalid replication_strategy is given", function()
      dao_config.replication_strategy = "foo"
      local err = first_migration.up(dao_config, migrations_stub)
      assert.truthy(err)
      assert.equal("invalid replication_strategy class", err)
    end)
  end)
end)
