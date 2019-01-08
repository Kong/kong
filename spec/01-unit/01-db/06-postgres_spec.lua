local config = {
  pg_database = "kong"
}


local connector = require "kong.db.strategies.postgres.connector".new(config)


describe("kong.db [#postgres] connector", function()
  describe(":infos()", function()
    it("returns infos db_ver always with two digit groups divided with dot (.)", function()
      local infos = connector.infos{ major_version = 9, major_minor_version = "9.5", config = config }
      assert.same({
        db_desc  = "database",
        db_ver   = "9.5",
        strategy = "PostgreSQL",
      }, infos)

      local infos = connector.infos{ major_version = 9.5, major_minor_version = "9.5", config = config }
      assert.same({
        db_desc  = "database",
        db_ver   = "9.5",
        strategy = "PostgreSQL",
      }, infos)

      infos = connector.infos{ major_version = 9, major_minor_version = "9.5.1", config = config }
      assert.same({
        db_desc  = "database",
        db_ver   = "9.5",
        strategy = "PostgreSQL",
      }, infos)

      infos = connector.infos{ major_version = 9.5, major_minor_version = "9.5.1", config = config }
      assert.same({
        db_desc  = "database",
        db_ver   = "9.5",
        strategy = "PostgreSQL",
      }, infos)

      infos = connector.infos{ major_version = 10, major_minor_version = "10.5", config = config }
      assert.same({
        db_desc  = "database",
        db_ver   = "10.5",
        strategy = "PostgreSQL",
      }, infos)
    end)

    it("returns infos with db_ver as \"unknown\" when missing major_minor_version", function()
      local infos = connector.infos{ major_version = 9, config = config }
      assert.same({
        db_desc  = "database",
        db_ver   = "unknown",
        strategy = "PostgreSQL",
      }, infos)

      infos = connector.infos{ major_version = 10, config = config }
      assert.same({
        db_desc  = "database",
        db_ver   = "unknown",
        strategy = "PostgreSQL",
      }, infos)

      infos = connector.infos{ config = config }
      assert.same({
        db_desc  = "database",
        db_ver   = "unknown",
        strategy = "PostgreSQL",
      }, infos)
    end)

    it("returns infos with db_ver as \"unknown\" when invalid major_minor_version", function()
      local infos = connector.infos{ major_version = 9, major_minor_version = "invalid", config = config }
      assert.same({
        db_desc  = "database",
        db_ver   = "unknown",
        strategy = "PostgreSQL",
      }, infos)

      infos = connector.infos{ major_version = 10, major_minor_version = "invalid", config = config }
      assert.same({
        db_desc  = "database",
        db_ver   = "unknown",
        strategy = "PostgreSQL",
      }, infos)

      infos = connector.infos{ major_minor_version = "invalid", config = config }
      assert.same({
        db_desc  = "database",
        db_ver   = "unknown",
        strategy = "PostgreSQL",
      }, infos)
    end)
  end)
end)
