local stringy = require "stringy"
local migrations = require "kong.dao.cassandra.schema.migrations"
local first_migration = migrations[1]

local function strip_query(str)
  str = stringy.split(str, ";")[1]
  str = str:gsub("\n", " "):gsub("%s+", " ")
  return stringy.strip(str)
end

describe("Cassandra migrations", function()
  describe("Keyspace options", function()
    it("should default to SimpleStrategy class with replication_factor of 1", function()
      local queries = first_migration.up({keyspace = "kong"})
      local keyspace_query = strip_query(queries)
      assert.equal("CREATE KEYSPACE IF NOT EXISTS \"kong\" WITH REPLICATION = {'class': 'SimpleStrategy', 'replication_factor': 1}", keyspace_query)
    end)
    it("should be possible to set a custom replication_factor", function()
      local queries = first_migration.up({keyspace = "kong", replication_factor = 2})
      local keyspace_query = strip_query(queries)
      assert.equal("CREATE KEYSPACE IF NOT EXISTS \"kong\" WITH REPLICATION = {'class': 'SimpleStrategy', 'replication_factor': 2}", keyspace_query)
    end)
    it("should accept NetworkTopologyStrategy", function()
      local queries = first_migration.up({
        keyspace = "kong",
        replication_strategy = "NetworkTopologyStrategy"
      })
      local keyspace_query = strip_query(queries)
      assert.equal("CREATE KEYSPACE IF NOT EXISTS \"kong\" WITH REPLICATION = {'class': 'NetworkTopologyStrategy'}", keyspace_query)
    end)
    it("should be possible to set data centers for NetworkTopologyStrategy", function()
      local queries = first_migration.up({
        keyspace = "kong",
        replication_strategy = "NetworkTopologyStrategy",
        data_centers = {
          dc1 = 2,
          dc2 = 3
        }
      })
      local keyspace_query = strip_query(queries)
      assert.equal("CREATE KEYSPACE IF NOT EXISTS \"kong\" WITH REPLICATION = {'class': 'NetworkTopologyStrategy', 'dc1': 2, 'dc2': 3}", keyspace_query)
    end)
    it("should return an error if an invalid replication_strategy is given", function()
      local queries, err = first_migration.up({
        keyspace = "kong",
        replication_strategy = "foo"
      })
      assert.falsy(queries)
      assert.equal("invalid replication_strategy class", err)
    end)
  end)
end)
