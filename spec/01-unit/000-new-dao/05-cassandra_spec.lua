local connector = require "kong.db.strategies.cassandra.connector"


describe("kong.db [#cassandra] connector", function()
  describe(":infos()", function()
    it("returns infos db_ver always with two digit groups divided with dot (.)", function()
      local infos = connector.infos{ major_version = 2, major_minor_version = "2.10" }
      assert.same({
        db_desc  = "keyspace",
        db_ver   = "2.10",
        strategy = "Cassandra",
      }, infos)

      infos = connector.infos{ major_version = 2, major_minor_version = "2.10.1" }
      assert.same({
        db_desc  = "keyspace",
        db_ver   = "2.10",
        strategy = "Cassandra",
      }, infos)

      infos = connector.infos{ major_version = 3, major_minor_version = "3.7" }
      assert.same({
        db_desc  = "keyspace",
        db_ver   = "3.7",
        strategy = "Cassandra",
      }, infos)
    end)

    it("returns infos with db_ver as \"unknown\" when missing major_minor_version", function()
      local infos = connector.infos{ major_version = 2 }
      assert.same({
        db_desc  = "keyspace",
        db_ver   = "unknown",
        strategy = "Cassandra",
      }, infos)

      infos = connector.infos{ major_version = 3 }
      assert.same({
        db_desc  = "keyspace",
        db_ver   = "unknown",
        strategy = "Cassandra",
      }, infos)

      infos = connector.infos{}
      assert.same({
        db_desc  = "keyspace",
        db_ver   = "unknown",
        strategy = "Cassandra",
      }, infos)
    end)

    it("returns infos with db_ver as \"unknown\" when invalid major_minor_version", function()
      local infos = connector.infos{ major_version = 2, major_minor_version = "invalid" }
      assert.same({
        db_desc  = "keyspace",
        db_ver   = "unknown",
        strategy = "Cassandra",
      }, infos)

      infos = connector.infos{ major_version = 3, major_minor_version = "invalid" }
      assert.same({
        db_desc  = "keyspace",
        db_ver   = "unknown",
        strategy = "Cassandra",
      }, infos)

      infos = connector.infos{ major_minor_version = "invalid" }
      assert.same({
        db_desc  = "keyspace",
        db_ver   = "unknown",
        strategy = "Cassandra",
      }, infos)
    end)
  end)
end)
