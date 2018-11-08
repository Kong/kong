local helpers = require "spec.helpers"

describe("kong start/stop", function()
  setup(function()
    helpers.get_db_utils() -- runs migrations
    helpers.prepare_prefix()
  end)
  after_each(function()
    helpers.kill_all()
  end)
  teardown(function()
    helpers.clean_prefix()
  end)

  it("start help", function()
    local _, stderr = helpers.kong_exec "start --help"
    assert.not_equal("", stderr)
  end)
  it("stop help", function()
    local _, stderr = helpers.kong_exec "stop --help"
    assert.not_equal("", stderr)
  end)
  it("start/stop gracefully with default conf/prefix", function()
    assert(helpers.kong_exec("start", {
      prefix = helpers.test_conf.prefix,
      database = helpers.test_conf.database,
      pg_database = helpers.test_conf.pg_database,
      cassandra_keyspace = helpers.test_conf.cassandra_keyspace
    }))
    assert(helpers.kong_exec("stop", {
      prefix = helpers.test_conf.prefix,
    }))
  end)
  it("start/stop custom Kong conf/prefix", function()
    assert(helpers.kong_exec("start --conf " .. helpers.test_conf_path))
    assert(helpers.kong_exec("stop --prefix " .. helpers.test_conf.prefix))
  end)
  it("start dumps Kong config in prefix", function()
    assert(helpers.kong_exec("start --conf " .. helpers.test_conf_path))
    assert.truthy(helpers.path.exists(helpers.test_conf.kong_env))
  end)
  it("creates prefix directory if it doesn't exist", function()
    finally(function()
      helpers.kill_all("foobar")
      pcall(helpers.dir.rmtree, "foobar")
    end)

    assert.falsy(helpers.path.exists("foobar"))
    assert(helpers.kong_exec("start --prefix foobar", {
      pg_database = helpers.test_conf.pg_database,
      cassandra_keyspace = helpers.test_conf.cassandra_keyspace,
    }))
    assert.truthy(helpers.path.exists("foobar"))
  end)

  describe("verbose args", function()
    it("accepts verbose --v", function()
      local _, _, stdout = assert(helpers.kong_exec("start --v --conf " .. helpers.test_conf_path))
      assert.matches("[verbose] prefix in use: ", stdout, nil, true)
    end)
    it("accepts debug --vv", function()
      local _, _, stdout = assert(helpers.kong_exec("start --vv --conf " .. helpers.test_conf_path))
      assert.matches("[verbose] prefix in use: ", stdout, nil, true)
      assert.matches("[debug] prefix = ", stdout, nil, true)
      assert.matches("[debug] database = ", stdout, nil, true)
    end)
    it("prints ENV variables when detected #postgres", function()
      local _, _, stdout = assert(helpers.kong_exec("start --vv --conf " .. helpers.test_conf_path, {
        database = "postgres",
        admin_listen = "127.0.0.1:8001"
      }))
      assert.matches('KONG_DATABASE ENV found with "postgres"', stdout, nil, true)
      assert.matches('KONG_ADMIN_LISTEN ENV found with "127.0.0.1:8001"', stdout, nil, true)
    end)
    it("prints config in alphabetical order", function()
      local _, _, stdout = assert(helpers.kong_exec("start --vv --conf " .. helpers.test_conf_path))
      assert.matches("admin_listen.*anonymous_reports.*cassandra_ssl.*prefix.*", stdout)
    end)
    it("does not print sensitive settings in config", function()
      local _, _, stdout = assert(helpers.kong_exec("start --vv --conf " .. helpers.test_conf_path, {
        pg_password = "do not print",
        cassandra_password = "do not print",
      }))
      assert.matches('KONG_PG_PASSWORD ENV found with "******"', stdout, nil, true)
      assert.matches('KONG_CASSANDRA_PASSWORD ENV found with "******"', stdout, nil, true)
      assert.matches('pg_password = "******"', stdout, nil, true)
      assert.matches('cassandra_password = "******"', stdout, nil, true)
    end)
  end)

  describe("custom --nginx-conf", function()
    local templ_fixture = "spec/fixtures/custom_nginx.template"

    it("accept a custom Nginx configuration", function()
      assert(helpers.kong_exec("start --conf " .. helpers.test_conf_path .. " --nginx-conf " .. templ_fixture))
      assert.truthy(helpers.path.exists(helpers.test_conf.nginx_conf))

      local contents = helpers.file.read(helpers.test_conf.nginx_conf)
      assert.matches("# This is a custom nginx configuration template for Kong specs", contents, nil, true)
      assert.matches("daemon on;", contents, nil, true)
    end)
  end)

  describe("/etc/hosts resolving in CLI", function()
    it("resolves #cassandra hostname", function()
      assert(helpers.kong_exec("start --vv --run-migrations --conf " .. helpers.test_conf_path, {
        cassandra_contact_points = "localhost",
        database = "cassandra"
      }))
    end)
    it("resolves #postgres hostname", function()
      assert(helpers.kong_exec("start --conf " .. helpers.test_conf_path, {
        pg_host = "localhost",
        database = "postgres"
      }))
    end)
  end)

  -- TODO: update with new error messages and behavior
  pending("--run-migrations", function()
    before_each(function()
      helpers.dao:drop_schema()
    end)
    after_each(function()
      helpers.dao:drop_schema()
      helpers.dao:run_migrations()
    end)

    describe("errors", function()
      it("does not start with an empty datastore", function()
        local ok, stderr  = helpers.kong_exec("start --conf "..helpers.test_conf_path)
        assert.False(ok)
        assert.matches("the current database schema does not match this version of Kong.", stderr)
      end)
      it("does not start if migrations are not up to date", function()
        helpers.dao:run_migrations()
        -- Delete a migration to simulate inconsistencies between version
        local _, err = helpers.dao.db:query([[
          DELETE FROM schema_migrations WHERE id='rate-limiting'
        ]])
        assert.is_nil(err)

        local ok, stderr  = helpers.kong_exec("start --conf "..helpers.test_conf_path)
        assert.False(ok)
        assert.matches("the current database schema does not match this version of Kong.", stderr)
      end)
      it("connection check errors are prefixed with DB-specific prefix", function()
        local ok, stderr = helpers.kong_exec("start --conf " .. helpers.test_conf_path, {
          pg_port = 99999,
          cassandra_port = 99999,
        })
        assert.False(ok)
        assert.matches("[" .. helpers.test_conf.database .. " error]", stderr, 1, true)
      end)
    end)
  end)

  describe("nginx_daemon = off", function()
    it("redirects nginx's stdout to 'kong start' stdout", function()
      local pl_utils = require "pl.utils"
      local pl_file = require "pl.file"

      local stdout_path = os.tmpname()

      finally(function()
        os.remove(stdout_path)
      end)

      local cmd = string.format("KONG_PROXY_ACCESS_LOG=/dev/stdout "    ..
                                "KONG_NGINX_DAEMON=off %s start -c %s " ..
                                ">%s 2>/dev/null &", helpers.bin_path,
                                helpers.test_conf_path, stdout_path)

      local ok, _, _, stderr = pl_utils.executeex(cmd)
      if not ok then
        error(stderr)
      end

      do
        local proxy_client

        -- get a connection, retry until kong starts
        helpers.wait_until(function()
          local pok
          pok, proxy_client = pcall(helpers.proxy_client)
          return pok
        end, 10)

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/hello",
        })
        assert.res_status(404, res) -- no API configured
      end

      assert(helpers.stop_kong(helpers.test_conf.prefix))

      -- TEST: since nginx started in the foreground, the 'kong start' command
      -- stdout should receive all of nginx's stdout as well.
      local stdout = pl_file.read(stdout_path)
      assert.matches([["GET /hello HTTP/1.1" 404]] , stdout, nil, true)
    end)
  end)

  describe("errors", function()
    it("start inexistent Kong conf file", function()
      local ok, stderr = helpers.kong_exec "start --conf foobar.conf"
      assert.False(ok)
      assert.is_string(stderr)
      assert.matches("Error: no file at: foobar.conf", stderr, nil, true)
    end)
    it("stop inexistent prefix", function()
      assert(helpers.kong_exec("start --prefix " .. helpers.test_conf.prefix, {
        pg_database = helpers.test_conf.pg_database,
        cassandra_keyspace = helpers.test_conf.cassandra_keyspace,
      }))

      local ok, stderr = helpers.kong_exec("stop --prefix inexistent")
      assert.False(ok)
      assert.matches("Error: no such prefix: .*/inexistent", stderr)
    end)
    it("notifies when Kong is already running", function()
      assert(helpers.kong_exec("start --prefix " .. helpers.test_conf.prefix, {
        pg_database = helpers.test_conf.pg_database,
        cassandra_keyspace = helpers.test_conf.cassandra_keyspace,
      }))

      local ok, stderr = helpers.kong_exec("start --prefix " .. helpers.test_conf.prefix, {
        pg_database = helpers.test_conf.pg_database
      })
      assert.False(ok)
      assert.matches("Kong is already running in " .. helpers.test_conf.prefix, stderr, nil, true)
    end)
    it("should not stop Kong if already running in prefix", function()
      local kill = require "kong.cmd.utils.kill"

      assert(helpers.kong_exec("start --prefix " .. helpers.test_conf.prefix, {
        pg_database = helpers.test_conf.pg_database,
        cassandra_keyspace = helpers.test_conf.cassandra_keyspace,
      }))

      local ok, stderr = helpers.kong_exec("start --prefix " .. helpers.test_conf.prefix, {
        pg_database = helpers.test_conf.pg_database
      })
      assert.False(ok)
      assert.matches("Kong is already running in " .. helpers.test_conf.prefix, stderr, nil, true)

      assert(kill.is_running(helpers.test_conf.nginx_pid))
    end)
    it("ensures the required shared dictionaries are defined", function()
      local constants = require "kong.constants"
      local pl_file   = require "pl.file"
      local fmt       = string.format

      local templ_fixture     = "spec/fixtures/custom_nginx.template"
      local new_templ_fixture = "spec/fixtures/custom_nginx.template.tmp"

      finally(function()
        pl_file.delete(new_templ_fixture)
        helpers.stop_kong()
      end)

      for _, dict in ipairs(constants.DICTS) do
        -- remove shared dictionary entry
        assert(os.execute(fmt("sed '/lua_shared_dict %s .*;/d' %s > %s",
                              dict, templ_fixture, new_templ_fixture)))

        local ok, err = helpers.start_kong({ nginx_conf = new_templ_fixture })
        assert.falsy(ok)
        assert.matches(
          "missing shared dict '" .. dict .. "' in Nginx configuration, "    ..
          "are you using a custom template? Make sure the 'lua_shared_dict " ..
          dict .. " [SIZE];' directive is defined.", err, nil, true)
      end
    end)
  end)
end)
