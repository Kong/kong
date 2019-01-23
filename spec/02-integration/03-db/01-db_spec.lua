local DB      = require "kong.db"
local helpers = require "spec.helpers"
local utils   = require "kong.tools.utils"


for _, strategy in helpers.each_strategy() do
  local it_ssl = strategy == "cassandra" and pending or it


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
    lazy_setup(function()
      helpers.get_db_utils(strategy, {})
    end)

    it("returns opened connection when using cosockets", function()
      -- bin/busted runs with ngx.IS_CLI = true, which forces luasocket to
      -- be used in the DB connector (for custom CAs to work)
      -- Disable this behavior for this test, especially considering we
      -- are running within resty-cli, and thus within timer_by_lua (which
      -- can support cosockets).
      ngx.IS_CLI = false

      local db, err = DB.new(helpers.test_conf, strategy)
      assert.is_nil(err)
      assert.is_table(db)

      assert(db:init_connector())

      local conn, err = db:connect()
      assert.is_nil(err)
      assert.is_table(conn)

      if strategy == "postgres" then
        assert.equal("nginx", db.connector:get_stored_connection().sock_type)
      --elseif strategy == "cassandra" then
      --TODO: cassandra forces luasocket on timer
      end

      assert.is_false(db.connector:get_stored_connection().ssl)

      db:close()
    end)

    it("returns opened connection when using luasocket", function()
      ngx.IS_CLI = true

      local db, err = DB.new(helpers.test_conf, strategy)
      assert.is_nil(err)
      assert.is_table(db)

      assert(db:init_connector())

      local conn, err = db:connect()
      assert.is_nil(err)
      assert.is_table(conn)

      if strategy == "postgres" then
        assert.equal("luasocket",
                     db.connector:get_stored_connection().sock_type)
      --elseif strategy == "cassandra" then
      --TODO: cassandra forces luasocket on timer
      end

      assert.is_false(db.connector:get_stored_connection().ssl)

      db:close()
    end)

    it_ssl("returns opened connection with ssl (cosockets)", function()
      ngx.IS_CLI = false

      local conf = utils.deep_copy(helpers.test_conf)

      conf.pg_ssl = true
      conf.cassandra_ssl = true

      local db, err = DB.new(conf, strategy)
      assert.is_nil(err)
      assert.is_table(db)

      assert(db:init_connector())

      local conn, err = db:connect()
      assert.is_nil(err)
      assert.is_table(conn)

      if strategy == "postgres" then
        assert.equal("nginx", db.connector:get_stored_connection().sock_type)
      --elseif strategy == "cassandra" then
      --TODO: cassandra forces luasocket on timer
      end

      assert.is_true(db.connector:get_stored_connection().ssl)

      db:close()
    end)

    it_ssl("returns opened connection with ssl (luasocket)", function()
      ngx.IS_CLI = true

      local conf = utils.deep_copy(helpers.test_conf)

      conf.pg_ssl = true
      conf.cassandra_ssl = true

      local db, err = DB.new(conf, strategy)
      assert.is_nil(err)
      assert.is_table(db)

      assert(db:init_connector())

      local conn, err = db:connect()
      assert.is_nil(err)
      assert.is_table(conn)

      if strategy == "postgres" then
        assert.equal("luasocket",
                     db.connector:get_stored_connection().sock_type)
      --elseif strategy == "cassandra" then
      --TODO: cassandra forces luasocket on timer
      end

      assert.is_true(db.connector:get_stored_connection().ssl)

      db:close()
    end)
  end)


  describe(":setkeepalive() [#" .. strategy .. "]", function()
    lazy_setup(function()
      helpers.get_db_utils(strategy, {})
    end)

    it("returns true when there is a stored connection (cosockets)", function()
      ngx.IS_CLI = false

      local db, err = DB.new(helpers.test_conf, strategy)
      assert.is_nil(err)
      assert.is_table(db)

      assert(db:init_connector())

      local conn, err = db:connect()
      assert.is_nil(err)
      assert.is_table(conn)

      if strategy == "postgres" then
        assert.equal("nginx", db.connector:get_stored_connection().sock_type)
      --elseif strategy == "cassandra" then
      --TODO: cassandra forces luasocket on timer
      end

      assert.is_false(db.connector:get_stored_connection().ssl)
      assert.is_true(db:setkeepalive())

      db:close()
    end)

    it("returns true when there is a stored connection (luasocket)", function()
      ngx.IS_CLI = true

      local db, err = DB.new(helpers.test_conf, strategy)
      assert.is_nil(err)
      assert.is_table(db)

      assert(db:init_connector())

      local conn, err = db:connect()
      assert.is_nil(err)
      assert.is_table(conn)

      if strategy == "postgres" then
        assert.equal("luasocket",
                     db.connector:get_stored_connection().sock_type)
      --elseif strategy == "cassandra" then
      --TODO: cassandra forces luasocket on timer
      end

      assert.is_false(db.connector:get_stored_connection().ssl)
      assert.is_true(db:setkeepalive())

      db:close()
    end)

    it_ssl("returns true when there is a stored connection with ssl (cosockets)", function()
      ngx.IS_CLI = false

      local conf = utils.deep_copy(helpers.test_conf)

      conf.pg_ssl = true
      conf.cassandra_ssl = true

      local db, err = DB.new(conf, strategy)
      assert.is_nil(err)
      assert.is_table(db)

      assert(db:init_connector())

      local conn, err = db:connect()
      assert.is_nil(err)
      assert.is_table(conn)

      if strategy == "postgres" then
        assert.equal("nginx", db.connector:get_stored_connection().sock_type)
      --elseif strategy == "cassandra" then
      --TODO: cassandra forces luasocket on timer
      end

      assert.is_true(db.connector:get_stored_connection().ssl)
      assert.is_true(db:setkeepalive())

      db:close()
    end)

    it_ssl("returns true when there is a stored connection with ssl (luasocket)", function()
      ngx.IS_CLI = true

      local conf = utils.deep_copy(helpers.test_conf)

      conf.pg_ssl = true
      conf.cassandra_ssl = true

      local db, err = DB.new(conf, strategy)
      assert.is_nil(err)
      assert.is_table(db)

      assert(db:init_connector())

      local conn, err = db:connect()
      assert.is_nil(err)
      assert.is_table(conn)

      if strategy == "postgres" then
        assert.equal("luasocket",
                     db.connector:get_stored_connection().sock_type)
      --elseif strategy == "cassandra" then
      --TODO: cassandra forces luasocket on timer
      end

      assert.is_true(db.connector:get_stored_connection().ssl)
      assert.is_true(db:setkeepalive())

      db:close()
    end)

    it("returns true when there is no stored connection (cosockets)", function()
      ngx.IS_CLI = false

      local db, err = DB.new(helpers.test_conf, strategy)
      assert.is_nil(err)
      assert.is_table(db)

      assert(db:init_connector())

      assert.is_nil(db.connector:get_stored_connection())
      assert.is_true(db:setkeepalive())
    end)

    it("returns true when there is no stored connection (luasocket)", function()
      ngx.IS_CLI = true

      local db, err = DB.new(helpers.test_conf, strategy)
      assert.is_nil(err)
      assert.is_table(db)

      assert(db:init_connector())

      assert.is_nil(db.connector:get_stored_connection())
      assert.is_true(db:setkeepalive())
    end)
  end)


  describe(":close() [#" .. strategy .. "]", function()
    lazy_setup(function()
      helpers.get_db_utils(strategy, {})
    end)

    it("returns true when there is a stored connection (cosockets)", function()
      ngx.IS_CLI = false

      local db, err = DB.new(helpers.test_conf, strategy)
      assert.is_nil(err)
      assert.is_table(db)

      assert(db:init_connector())

      local conn, err = db:connect()
      assert.is_nil(err)
      assert.is_table(conn)

      if strategy == "postgres" then
        assert.equal("nginx", db.connector:get_stored_connection().sock_type)
      --elseif strategy == "cassandra" then
      --TODO: cassandra forces luasocket on timer
      end

      assert.is_false(db.connector:get_stored_connection().ssl)
      assert.is_true(db:close())
    end)

    it("returns true when there is a stored connection (luasocket)", function()
      ngx.IS_CLI = true

      local db, err = DB.new(helpers.test_conf, strategy)
      assert.is_nil(err)
      assert.is_table(db)

      assert(db:init_connector())

      local conn, err = db:connect()
      assert.is_nil(err)
      assert.is_table(conn)

      if strategy == "postgres" then
        assert.equal("luasocket", db.connector:get_stored_connection().sock_type)
      --elseif strategy == "cassandra" then
      --TODO: cassandra forces luasocket on timer
      end

      assert.is_false(db.connector:get_stored_connection().ssl)
      assert.is_true(db:close())
    end)

    it_ssl("returns true when there is a stored connection with ssl (cosockets)", function()
      ngx.IS_CLI = false

      local conf = utils.deep_copy(helpers.test_conf)

      conf.pg_ssl = true
      conf.cassandra_ssl = true

      local db, err = DB.new(conf, strategy)
      assert.is_nil(err)
      assert.is_table(db)

      assert(db:init_connector())

      local conn, err = db:connect()
      assert.is_nil(err)
      assert.is_table(conn)

      if strategy == "postgres" then
        assert.equal("nginx", db.connector:get_stored_connection().sock_type)
      --elseif strategy == "cassandra" then
      --TODO: cassandra forces luasocket on timer
      end

      assert.is_true(db.connector:get_stored_connection().ssl)
      assert.is_true(db:close())
    end)

    it_ssl("returns true when there is a stored connection with ssl (luasocket)", function()
      ngx.IS_CLI = true

      local conf = utils.deep_copy(helpers.test_conf)

      conf.pg_ssl = true
      conf.cassandra_ssl = true

      local db, err = DB.new(conf, strategy)
      assert.is_nil(err)
      assert.is_table(db)

      assert(db:init_connector())

      local conn, err = db:connect()
      assert.is_nil(err)
      assert.is_table(conn)

      if strategy == "postgres" then
        assert.equal("luasocket",
                     db.connector:get_stored_connection().sock_type)
      --elseif strategy == "cassandra" then
      --TODO: cassandra forces luasocket on timer
      end

      assert.is_true(db.connector:get_stored_connection().ssl)
      assert.is_true(db:close())
    end)

    it("returns true when there is no stored connection (cosockets)", function()
      ngx.IS_CLI = false

      local db, err = DB.new(helpers.test_conf, strategy)
      assert.is_nil(err)
      assert.is_table(db)

      assert(db:init_connector())

      assert.is_nil(db.connector:get_stored_connection())
      assert.is_true(db:close())
    end)

    it("returns true when there is no stored connection (luasocket)", function()
      ngx.IS_CLI = true

      local db, err = DB.new(helpers.test_conf, strategy)
      assert.is_nil(err)
      assert.is_table(db)

      assert(db:init_connector())

      assert.is_nil(db.connector:get_stored_connection())
      assert.equal(true, db:close())
    end)
  end)
end
