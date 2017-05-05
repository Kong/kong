local helpers = require "spec.helpers"

describe("kong start/stop", function()
  setup(function()
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
  pending("start/stop gracefully with default conf/prefix", function()
    -- don't want to force migrations to be run on default
    -- keyspace/database
    assert(helpers.kong_exec("start", {
      database = helpers.test_conf.database,
      pg_database = helpers.test_conf.pg_database,
      cassandra_keyspace = helpers.test_conf.cassandra_keyspace
    }))
    assert(helpers.kong_exec "stop")
  end)
  it("start/stop custom Kong conf/prefix", function()
    assert(helpers.kong_exec("start --conf "..helpers.test_conf_path))
    assert(helpers.kong_exec("stop --prefix "..helpers.test_conf.prefix))
  end)
  it("start dumps Kong config in prefix", function()
    assert(helpers.kong_exec("start --conf "..helpers.test_conf_path))
    assert.truthy(helpers.path.exists(helpers.test_conf.kong_env))
  end)
  it("creates prefix directory if it doesn't exist", function()
    finally(function()
      helpers.kill_all("foobar")
      pcall(helpers.dir.rmtree, "foobar")
    end)

    assert.falsy(helpers.path.exists("foobar"))
    assert(helpers.kong_exec("start --prefix foobar", {
      pg_database = helpers.test_conf.pg_database
    }))
    assert.truthy(helpers.path.exists("foobar"))
  end)

  describe("verbose args", function()
    it("accepts verbose --v", function()
      local _, _, stdout = assert(helpers.kong_exec("start --v --conf "..helpers.test_conf_path))
      assert.matches("[verbose] prefix in use: ", stdout, nil, true)
    end)
    it("accepts debug --vv", function()
      local _, _, stdout = assert(helpers.kong_exec("start --vv --conf "..helpers.test_conf_path))
      assert.matches("[verbose] prefix in use: ", stdout, nil, true)
      assert.matches("[debug] prefix = ", stdout, nil, true)
      assert.matches("[debug] database = ", stdout, nil, true)
    end)
    it("prints ENV variables when detected", function()
      local _, _, stdout = assert(helpers.kong_exec("start --vv --conf "..helpers.test_conf_path, {
        database = "postgres",
        admin_listen = "127.0.0.1:8001"
      }))
      assert.matches('KONG_DATABASE ENV found with "postgres"', stdout, nil, true)
      assert.matches('KONG_ADMIN_LISTEN ENV found with "127.0.0.1:8001"', stdout, nil, true)
    end)
    it("prints config in alphabetical order", function()
      local _, _, stdout = assert(helpers.kong_exec("start --vv --conf "..helpers.test_conf_path))
      assert.matches("admin_listen.*anonymous_reports.*cassandra_ssl.*prefix.*", stdout)
    end)
    it("does not print sensitive settings in config", function()
      local _, _, stdout = assert(helpers.kong_exec("start --vv --conf "..helpers.test_conf_path, {
        pg_password = "do not print",
        cassandra_password = "do not print",
        cluster_encrypt_key = "fHGfspTRljmzLsYDVEK1Rw=="
      }))
      assert.matches('KONG_PG_PASSWORD ENV found with "******"', stdout, nil, true)
      assert.matches('KONG_CASSANDRA_PASSWORD ENV found with "******"', stdout, nil, true)
      assert.matches('KONG_CLUSTER_ENCRYPT_KEY ENV found with "******"', stdout, nil, true)
      assert.matches('pg_password = "******"', stdout, nil, true)
      assert.matches('cassandra_password = "******"', stdout, nil, true)
      assert.matches('cluster_encrypt_key = "******"', stdout, nil, true)
    end)
  end)

  describe("custom --nginx-conf", function()
    local templ_fixture = "spec/fixtures/custom_nginx.template"

    it("accept a custom Nginx configuration", function()
      assert(helpers.kong_exec("start --conf "..helpers.test_conf_path.." --nginx-conf "..templ_fixture))
      assert.truthy(helpers.path.exists(helpers.test_conf.nginx_conf))

      local contents = helpers.file.read(helpers.test_conf.nginx_conf)
      assert.matches("# This is a custom nginx configuration template for Kong specs", contents, nil, true)
      assert.matches("daemon on;", contents, nil, true)
    end)
  end)

  describe("/etc/hosts resolving in CLI", function()
    it("resolves #cassandra hostname", function()
      assert(helpers.kong_exec("start --vv --conf "..helpers.test_conf_path, {
        cassandra_contact_points = "localhost",
        database = "cassandra"
      }))
    end)
    it("resolves #postgres hostname", function()
      assert(helpers.kong_exec("start --conf "..helpers.test_conf_path, {
        pg_host = "localhost",
        database = "postgres"
      }))
    end)
  end)

  describe("Serf", function()
    it("starts Serf agent daemon", function()
      assert(helpers.kong_exec("start --conf "..helpers.test_conf_path))

      local cmd = string.format("kill -0 `cat %s` >/dev/null 2>&1", helpers.test_conf.serf_pid)
      assert(helpers.execute(cmd))
    end)
    it("recovers from expired serf.pid file", function()
      assert(helpers.execute("touch "..helpers.test_conf.serf_pid)) -- dumb pid
      assert(helpers.kong_exec("start --conf "..helpers.test_conf_path))

      local cmd = string.format("kill -0 `cat %s` >/dev/null 2>&1", helpers.test_conf.serf_pid)
      assert(helpers.execute(cmd))
    end)
    it("dumps PID in prefix", function()
      assert(helpers.kong_exec("start --conf "..helpers.test_conf_path))
      assert.truthy(helpers.path.exists(helpers.test_conf.serf_pid))
      assert(helpers.kong_exec("stop --prefix "..helpers.test_conf.prefix))
      ngx.sleep(2)
      assert.False(helpers.path.exists(helpers.test_conf.serf_pid))
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
      assert(helpers.kong_exec("start --prefix "..helpers.test_conf.prefix, {
        pg_database = helpers.test_conf.pg_database
      }))

      local ok, stderr = helpers.kong_exec("stop --prefix inexistent")
      assert.False(ok)
      assert.matches("Error: no such prefix: .*/inexistent", stderr)
    end)
    it("notifies when Kong is already running", function()
      assert(helpers.kong_exec("start --prefix "..helpers.test_conf.prefix, {
        pg_database = helpers.test_conf.pg_database
      }))

      local ok, stderr = helpers.kong_exec("start --prefix "..helpers.test_conf.prefix, {
        pg_database = helpers.test_conf.pg_database
      })
      assert.False(ok)
      assert.matches("Kong is already running in "..helpers.test_conf.prefix, stderr, nil, true)
    end)
    it("stops other services when could not start", function()
      local kill = require "kong.cmd.utils.kill"
      local thread = helpers.tcp_server(helpers.test_conf.proxy_port)
      finally(function()
        -- make tcp server receive and close
        helpers.proxy_client():send {
          method = "GET",
          path = "/"
        }
        thread:join()
      end)

      local ok, err = helpers.kong_exec("start --conf "..helpers.test_conf_path)
      assert.False(ok)
      assert.matches("Address already in use", err, nil, true)

      assert.falsy(kill.is_running(helpers.test_conf.serf_pid))
    end)
    it("should not stop Kong if already running in prefix", function()
      local kill = require "kong.cmd.utils.kill"

      assert(helpers.kong_exec("start --prefix "..helpers.test_conf.prefix, {
        pg_database = helpers.test_conf.pg_database
      }))

      local ok, stderr = helpers.kong_exec("start --prefix "..helpers.test_conf.prefix, {
        pg_database = helpers.test_conf.pg_database
      })
      assert.False(ok)
      assert.matches("Kong is already running in "..helpers.test_conf.prefix, stderr, nil, true)

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
