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

    it("returns connection", function()
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

      assert.equal(false, db.connector:get_stored_connection().ssl)

      db:close()
    end)

    it("returns connection using luasocket", function()
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

      assert.equal(false, db.connector:get_stored_connection().ssl)

      db:close()
    end)

    it_ssl("returns connection with ssl", function()
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

      assert.equal(true, db.connector:get_stored_connection().ssl)

      db:close()
    end)

    it_ssl("returns connection using luasocket with ssl", function()
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
        assert.equal("luasocket", db.connector:get_stored_connection().sock_type)
      --elseif strategy == "cassandra" then
      --TODO: cassandra forces luasocket on timer
      end

      assert.equal(true, db.connector:get_stored_connection().ssl)

      db:close()
    end)
  end)


  describe(":setkeepalive() [#" .. strategy .. "]", function()
    lazy_setup(function()
      helpers.get_db_utils(strategy, {})
    end)

    it("return true when there is a stored connection", function()
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

      assert.equal(false, db.connector:get_stored_connection().ssl)
      assert.equal(true, db:setkeepalive())

      db:close()
    end)

    it("return true when there is a stored connection using luasocket", function()
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

      assert.equal(false, db.connector:get_stored_connection().ssl)
      assert.equal(true, db:setkeepalive())

      db:close()
    end)

    it_ssl("return true when there is a stored connection with ssl", function()
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

      assert.equal(true, db.connector:get_stored_connection().ssl)
      assert.equal(true, db:setkeepalive())

      db:close()
    end)

    it_ssl("return true when there is a stored connection using luasocket with ssl", function()
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
        assert.equal("luasocket", db.connector:get_stored_connection().sock_type)
      --elseif strategy == "cassandra" then
      --TODO: cassandra forces luasocket on timer
      end

      assert.equal(true, db.connector:get_stored_connection().ssl)
      assert.equal(true, db:setkeepalive())

      db:close()
    end)


    it("return true when there is no stored connection", function()
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

      assert.equal(false, db.connector:get_stored_connection().ssl)

      db:close()

      assert.is_nil(db.connector:get_stored_connection())
      assert.equal(true, db:setkeepalive())
    end)

    it("return true when there is no stored connection using luasocket", function()
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

      assert.equal(false, db.connector:get_stored_connection().ssl)

      db:close()

      assert.is_nil(db.connector:get_stored_connection())
      assert.equal(true, db:setkeepalive())
    end)


    it_ssl("return true when there is no stored connection with ssl", function()
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

      assert.equal(true, db.connector:get_stored_connection().ssl)

      db:close()

      assert.is_nil(db.connector:get_stored_connection())
      assert.equal(true, db:setkeepalive())
    end)

    it_ssl("return true when there is no stored connection using luasocket with ssl", function()
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
        assert.equal("luasocket", db.connector:get_stored_connection().sock_type)
      --elseif strategy == "cassandra" then
      --TODO: cassandra forces luasocket on timer
      end

      assert.equal(true, db.connector:get_stored_connection().ssl)

      db:close()

      assert.is_nil(db.connector:get_stored_connection())
      assert.equal(true, db:setkeepalive())
    end)
  end)

  describe(":close() [#" .. strategy .. "]", function()
    lazy_setup(function()
      helpers.get_db_utils(strategy, {})
    end)

    it("return true when there is a stored connection", function()
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

      assert.equal(false, db.connector:get_stored_connection().ssl)
      assert.equal(true, db:close())
    end)

    it("return true when there is a stored connection using luasocket", function()
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

      assert.equal(false, db.connector:get_stored_connection().ssl)
      assert.equal(true, db:close())
    end)

    it_ssl("return true when there is a stored connection with ssl", function()
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

      assert.equal(true, db.connector:get_stored_connection().ssl)
      assert.equal(true, db:close())
    end)

    it_ssl("return true when there is a stored connection using luasocket with ssl", function()
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
        assert.equal("luasocket", db.connector:get_stored_connection().sock_type)
      --elseif strategy == "cassandra" then
      --TODO: cassandra forces luasocket on timer
      end

      assert.equal(true, db.connector:get_stored_connection().ssl)
      assert.equal(true, db:close())
    end)

    it("return true when there is no stored connection", function()
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

      assert.equal(false, db.connector:get_stored_connection().ssl)

      db:close()

      assert.is_nil(db.connector:get_stored_connection())
      assert.equal(true, db:close())
    end)

    it("return true when there is no stored connection using luasocket", function()
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

      assert.equal(false, db.connector:get_stored_connection().ssl)

      db:close()

      assert.is_nil(db.connector:get_stored_connection())
      assert.equal(true, db:close())
    end)

    it_ssl("return true when there is no stored connection with ssl", function()
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

      assert.equal(true, db.connector:get_stored_connection().ssl)

      db:close()

      assert.is_nil(db.connector:get_stored_connection())
      assert.equal(true, db:close())
    end)

    it_ssl("return true when there is no stored connection using luasocket with ssl", function()
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
        assert.equal("luasocket", db.connector:get_stored_connection().sock_type)
      --elseif strategy == "cassandra" then
      --TODO: cassandra forces luasocket on timer
      end

      assert.equal(true, db.connector:get_stored_connection().ssl)

      db:close()

      assert.is_nil(db.connector:get_stored_connection())
      assert.equal(true, db:close())
    end)
  end)
end
