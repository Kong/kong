local DB      = require "kong.db"
local helpers = require "spec.helpers"
local utils   = require "kong.tools.utils"


for _, strategy in helpers.each_strategy() do
  local postgres_only = strategy == "postgres" and it or pending
  local cassandra_only = strategy == "cassandra" and it or pending


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
            db_readonly = false,
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

      postgres_only("initializes infos with custom schema", function()
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
          db_readonly = false,
        }, infos)

      end)

      postgres_only("initializes infos with readonly support", function()
        local conf = utils.deep_copy(helpers.test_conf)

        conf.pg_ro_host = "127.0.0.1"

        -- hack
        ngx.IS_CLI = false

        local db, err = DB.new(conf, strategy)

        -- hack
        ngx.IS_CLI = true

        assert.is_nil(err)
        assert.is_table(db)

        local infos = db.infos

        assert.same({
          strategy = "PostgreSQL",
          db_desc = "database",
          db_name = conf.pg_database,
          db_schema = helpers.test_conf.pg_schema or "",
          db_ver  = "unknown",
          db_readonly = true,
        }, infos)

      end)

      cassandra_only("errors when provided Cassandra contact points do not resolve DNS", function()
        local conf = utils.deep_copy(helpers.test_conf)

        conf.cassandra_contact_points = { "unknown", "unknown2" }

        local db, err = DB.new(conf, strategy)
        assert.is_nil(db)
        assert.equal(helpers.unindent([[
          could not resolve any of the provided Cassandra contact points
          (cassandra_contact_points = 'unknown, unknown2')
        ]], true, true), err)
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
          -- this depends on pg config, but for test-suite it is "public"
          -- when not specified-
          db_schema = helpers.test_conf.pg_schema or "public",
          db_ver  = infos.db_ver,
          db_readonly = false,
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

    postgres_only("initializes infos with custom schema", function()
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
        db_readonly = false,
      }, infos)
    end)

    if strategy ~= "off" then
      it("calls :check_version_compat with constants", function()
        local constants = require "kong.constants"
        local versions = constants.DATABASE[strategy:upper()]

        local db, _ = DB.new(helpers.test_conf, strategy)
        local s = spy.on(db, "check_version_compat")
        assert(db:init_connector())
        -- called_with goes on forever when checking for self
        assert.equal(versions.MIN, s.calls[1].refs[2])
        assert.equal(versions.DEPRECATED, s.calls[1].refs[3])
      end)
    end
  end)


  describe(":connect() [#" .. strategy .. "]", function()
    lazy_setup(function()
      helpers.get_db_utils(strategy, {})
    end)

    postgres_only("connects to schema configured in postgres by default", function()
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

    postgres_only("connects to custom schema when configured", function()
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

    cassandra_only("provided Cassandra contact points resolve DNS", function()
      local conf = utils.deep_copy(helpers.test_conf)

      conf.cassandra_contact_points = { "localhost" }

      local db, err = DB.new(conf, strategy)
      assert.is_nil(err)
      assert.is_table(db)

      assert(db:init_connector())

      local conn, err = db:connect()
      assert.is_nil(err)
      assert.is_table(conn)
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

    postgres_only("returns opened connection with ssl (cosockets)", function()
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

    postgres_only("returns opened connection with ssl (luasocket)", function()
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

    postgres_only("connects to postgres with readonly account (cosockets)", function()
      ngx.IS_CLI = false

      local conf = utils.deep_copy(helpers.test_conf)
      conf.pg_ro_host = conf.pg_host

      local db, err = DB.new(conf, strategy)
      assert.is_nil(err)
      assert.is_table(db)

      assert(db:init_connector())

      local conn, err = db.connector:connect("read")
      assert.is_nil(err)
      assert.is_table(conn)

      assert.is_nil(db.connector:get_stored_connection("write"))
      assert.is_nil(db.connector:get_stored_connection()) -- empty defaults to "write"

      assert.equal("nginx", db.connector:get_stored_connection("read").sock_type)
      assert.is_false(db.connector:get_stored_connection("read").ssl)

      db:close()
    end)

    postgres_only("connects to postgres with readonly account (luasocket)", function()
      ngx.IS_CLI = true

      local conf = utils.deep_copy(helpers.test_conf)
      conf.pg_ro_host = conf.pg_host

      local db, err = DB.new(conf, strategy)
      assert.is_nil(err)
      assert.is_table(db)

      assert(db:init_connector())

      local conn, err = db.connector:connect("read")
      -- this gets overwritten to write instead
      assert.is_nil(err)
      assert.is_table(conn)

      assert.is_nil(db.connector:get_stored_connection("read"))

      assert.equal("luasocket", db.connector:get_stored_connection("write").sock_type)
      assert.is_false(db.connector:get_stored_connection("write").ssl)

      assert.equal("luasocket", db.connector:get_stored_connection().sock_type)
      assert.is_false(db.connector:get_stored_connection().ssl)

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

    postgres_only("returns true when there is a stored connection with ssl (cosockets)", function()
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

    postgres_only("returns true when there is a stored connection with ssl (luasocket)", function()
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

    postgres_only("keepalives both read only and write connection (cosockets)", function()
      ngx.IS_CLI = false

      local conf = utils.deep_copy(helpers.test_conf)
      conf.pg_ro_host = conf.pg_host

      local db, err = DB.new(conf, strategy)
      assert.is_nil(err)
      assert.is_table(db)

      assert(db:init_connector())

      local conn, err = db.connector:connect("read")
      assert.is_nil(err)
      assert.is_table(conn)

      conn, err = db.connector:connect("write")
      assert.is_nil(err)
      assert.is_table(conn)

      assert.equal("nginx", db.connector:get_stored_connection("read").sock_type)
      assert.equal("nginx", db.connector:get_stored_connection("write").sock_type)

      assert.is_false(db.connector:get_stored_connection("read").ssl)
      assert.is_false(db.connector:get_stored_connection("write").ssl)

      assert.is_true(db:setkeepalive())

      assert.is_nil(db.connector:get_stored_connection("read"))
      assert.is_nil(db.connector:get_stored_connection("write"))

      db:close()
    end)

    postgres_only("connects and keepalives only write connection (luasocket)", function()
      ngx.IS_CLI = true

      local conf = utils.deep_copy(helpers.test_conf)
      conf.pg_ro_host = conf.pg_host

      local db, err = DB.new(conf, strategy)
      assert.is_nil(err)
      assert.is_table(db)

      assert(db:init_connector())

      local conn, err = db.connector:connect("read")
      -- this gets overwritten to "write" under the hood
      assert.is_nil(err)
      assert.is_table(conn)

      conn, err = db.connector:connect("write")
      assert.is_nil(err)
      assert.is_table(conn)

      assert.equal("luasocket", db.connector:get_stored_connection("write").sock_type)
      assert.is_nil(db.connector:get_stored_connection("read"))

      assert.is_false(db.connector:get_stored_connection("write").ssl)

      assert.is_true(db:setkeepalive())

      assert.is_nil(db.connector:get_stored_connection("read"))
      assert.is_nil(db.connector:get_stored_connection("write"))

      db:close()
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

    postgres_only("returns true when there is a stored connection with ssl (cosockets)", function()
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

    postgres_only("returns true when there is a stored connection with ssl (luasocket)", function()
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

    postgres_only("returns true when both read-only and write connection exists (cosockets)", function()
      ngx.IS_CLI = false

      local conf = utils.deep_copy(helpers.test_conf)
      conf.pg_ro_host = conf.pg_host

      local db, err = DB.new(conf, strategy)
      assert.is_nil(err)
      assert.is_table(db)

      assert(db:init_connector())

      local conn, err = db.connector:connect("read")
      assert.is_nil(err)
      assert.is_table(conn)

      conn, err = db.connector:connect("write")
      assert.is_nil(err)
      assert.is_table(conn)

      assert.equal("nginx", db.connector:get_stored_connection("read").sock_type)
      assert.equal("nginx", db.connector:get_stored_connection("write").sock_type)

      assert.is_false(db.connector:get_stored_connection("read").ssl)
      assert.is_false(db.connector:get_stored_connection("write").ssl)

      assert.is_true(db:close())

      assert.is_nil(db.connector:get_stored_connection("read"))
      assert.is_nil(db.connector:get_stored_connection("write"))

      db:close()
    end)

    postgres_only("returns true when both read-only and write connection exists (luasocket)", function()
      ngx.IS_CLI = true

      local conf = utils.deep_copy(helpers.test_conf)
      conf.pg_ro_host = conf.pg_host

      local db, err = DB.new(conf, strategy)
      assert.is_nil(err)
      assert.is_table(db)

      assert(db:init_connector())

      local conn, err = db.connector:connect("read")
      assert.is_nil(err)
      assert.is_table(conn)

      conn, err = db.connector:connect("write")
      assert.is_nil(err)
      assert.is_table(conn)

      assert.equal("luasocket", db.connector:get_stored_connection("write").sock_type)
      assert.is_nil(db.connector:get_stored_connection("read"))

      assert.is_false(db.connector:get_stored_connection("write").ssl)

      assert.is_true(db:close())

      assert.is_nil(db.connector:get_stored_connection("read"))
      assert.is_nil(db.connector:get_stored_connection("write"))

      db:close()
    end)
  end)
end
