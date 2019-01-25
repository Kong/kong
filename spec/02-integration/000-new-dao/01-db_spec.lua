local DB      = require "kong.db"
local helpers = require "spec.helpers"



for _, strategy in helpers.each_strategy() do
  describe("kong.db.init [#" .. strategy .. "]", function()
    describe(".new()", function()
      it("errors on invalid arg", function()
        assert.has_error(function()
          DB.new(nil, strategy)
        end, "missing kong_config")

        assert.has_error(function()
          DB.new(helpers.test_conf, 123)
        end, "strategy must be a string")
      end)

      it("instantiates a DB", function()
        local db, err = DB.new(helpers.test_conf, strategy)
        assert.is_nil(err)
        assert.is_table(db)
      end)

      it("initializes infos", function()
        local db, err = DB.new(helpers.test_conf, strategy)

        assert.is_nil(err)
        assert.is_table(db)

        local infos = db.infos

        if strategy == "postgres" then
          assert.same({
            strategy = "PostgreSQL",
            db_desc = "database",
            db_name = helpers.test_conf.pg_database,
            db_ver  = "unknown",
          }, infos)

        elseif strategy == "cassandra" then
          assert.same({
            strategy = "Cassandra",
            db_desc = "keyspace",
            db_name = helpers.test_conf.cassandra_keyspace,
            db_ver  = "unknown",
          }, infos)

        else
          error("unknown database")
        end
      end)
    end)
  end)


  describe(":init_connector() [#" .. strategy .. "]", function()
    it("initializes infos", function()
      local db, err = DB.new(helpers.test_conf, strategy)

      assert.is_nil(err)
      assert.is_table(db)

      assert(db:init_connector())

      local infos = db.infos

      assert.matches("^%d+%.?%d*%.?%d*$", infos.db_ver)
      assert.not_matches("%.$", infos.db_ver)


      if strategy == "postgres" then
        assert.same({
          strategy = "PostgreSQL",
          db_desc = "database",
          db_name = helpers.test_conf.pg_database,
          db_ver  = infos.db_ver,
        }, infos)

      elseif strategy == "cassandra" then
        assert.same({
          strategy = "Cassandra",
          db_desc = "keyspace",
          db_name = helpers.test_conf.cassandra_keyspace,
          db_ver  = infos.db_ver,
        }, infos)

      else
        error("unknown database")
      end
    end)

  end)


  describe(":connect() [#" .. strategy .. "]", function()

  end)


  describe(":setkeepalive() [#" .. strategy .. "]", function()

  end)

  describe(":close() [#" .. strategy .. "]", function()

  end)
end
