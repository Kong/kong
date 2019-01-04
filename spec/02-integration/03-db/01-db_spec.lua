local DB      = require "kong.db"
local helpers = require "spec.helpers"
local utils   = require "kong.tools.utils"


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
            db_schema = helpers.test_conf.pg_schema or "",
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

      if strategy == "postgres" then
        it("initializes infos with custom schema", function()
          local conf = utils.deep_copy(helpers.test_conf)

          conf.pg_schema = "demo"

          local db, err = DB.new(conf, strategy)

          assert.is_nil(err)
          assert.is_table(db)

          local infos = db.infos

          assert.same({
            strategy = "PostgreSQL",
            db_desc = "database",
            db_name = conf.pg_database,
            db_schema = conf.pg_schema,
            db_ver  = "unknown",
          }, infos)

        end)
      end
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
          -- this depends on pg config, but for test-suite it is "public"
          -- when not specified-
          db_schema = helpers.test_conf.pg_schema or "public",
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

    if strategy == "postgres" then
      it("initializes infos with custom schema", function()
        local conf = utils.deep_copy(helpers.test_conf)

        conf.pg_schema = "demo"

        local db, err = DB.new(conf, strategy)

        assert.is_nil(err)
        assert.is_table(db)

        assert(db:init_connector())

        local infos = db.infos

        assert.matches("^%d+%.?%d*%.?%d*$", infos.db_ver)
        assert.not_matches("%.$", infos.db_ver)

        assert.same({
          strategy = "PostgreSQL",
          db_desc = "database",
          db_name = conf.pg_database,
          db_schema = conf.pg_schema,
          db_ver  = infos.db_ver,
        }, infos)
      end)
    end
  end)

  describe(":connect() [#" .. strategy .. "]", function()
    if strategy == "postgres" then
      it("connects to schema configured in postgres by default", function()
        local db, err = DB.new(helpers.test_conf, strategy)

        assert.is_nil(err)
        assert.is_table(db)
        assert(db:init_connector())
        assert(db:connect())

        local res = assert(db.connector:query("SELECT CURRENT_SCHEMA AS schema;"))

        assert.is_table(res[1])
        -- in test suite the CURRENT_SCHEMA is public
        assert.equal("public", res[1]["schema"])

        assert(db:close())
      end)

      it("connects to custom schema when configured", function()
        local conf = utils.deep_copy(helpers.test_conf)

        conf.pg_schema = "demo"

        local db, err = DB.new(conf, strategy)

        assert.is_nil(err)
        assert.is_table(db)
        assert(db:init_connector())
        assert(db:connect())
        assert(db:reset())

        local res = assert(db.connector:query("SELECT CURRENT_SCHEMA AS schema;"))

        assert.is_table(res[1])
        assert.equal("demo", res[1]["schema"])

        assert(db:close())
      end)
    end
  end)

  describe(":setkeepalive() [#" .. strategy .. "]", function()
  end)

  describe(":close() [#" .. strategy .. "]", function()
  end)
end
