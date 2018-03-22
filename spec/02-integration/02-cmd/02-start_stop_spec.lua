local helpers = require "spec.helpers"
local pl_utils = require "pl.utils"
local pl_path = require "pl.path"

describe("kong start/stop", function()
  setup(function()
    assert(helpers.dao:run_migrations())
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
  it("#only start without daemonizing will properly log to stdout/stderr", function()
    --[[
    What are we testing exactly?
    When Kong starts, the cli commands will shell out to start the 'nginx'
    executable. The stdout/stderr of this command is redirected to be captured
    in case of errors.
    A problem arises when Kong runs in the foreground 'nginx_daemon=off', and
    the nginx log output is set to '/dev/stderr' and '/std/stdout'.
    In this case the shell command to start Kong will capture all output send
    to stdout/stderr by nginx. Which causes the tempfiles to grow uncontrolable.

    So when Kong is run in the foreground, no redirects should be used when
    starting Kong to prevent the above from happening. Or in other words we
    want the stdout/stderr of the "kong start" command to receive all output
    of the nginx logs. Instead of them being swallowed by the intermediary
    nginx start command (used by "kong start" under the hood).
    --]]
    local exec = os.execute  -- luacheck: ignore
    local stdout = pl_path.tmpname()
    local stderr = pl_path.tmpname()
    -- create a finalizer that will stop Kong and cleanup logfiles
    finally(function()
      os.remove(stdout)
      os.remove(stderr)
      os.execute = exec  -- luacheck: ignore
      assert(helpers.kong_exec("stop", {
        prefix = helpers.test_conf.prefix,
      }))
    end)
    -- catch the prepared start command (let the 'helpers' do
    -- the hard work of building the command)
    local start_cmd
    os.execute = function(cmd) start_cmd = cmd return true end  -- luacheck: ignore
    assert(helpers.kong_exec("start", {
      prefix = helpers.test_conf.prefix,
      database = helpers.test_conf.database,
      pg_database = helpers.test_conf.pg_database,
      cassandra_keyspace = helpers.test_conf.cassandra_keyspace,
      proxy_listen = "127.0.0.1:" .. helpers.test_conf.proxy_listeners[1].port,
      admin_listen = "127.0.0.1:" .. helpers.test_conf.admin_listeners[1].port,
      admin_access_log = "/dev/stdout",
      admin_error_log = "/dev/stderr",
      proxy_access_log = "/dev/stdout",
      proxy_error_log = "/dev/stderr",
      log_level = "debug",
      nginx_daemon = "off",
    }))
    os.execute = exec  -- luacheck: ignore
    -- remove the stdout/stderr redirects from the captured command
    -- and insert new ones for us to track
    start_cmd = start_cmd:match("^(.- bin/kong start).-$")
    start_cmd = start_cmd .. " > " .. stdout .. " 2> " .. stderr
    start_cmd = start_cmd .. " &"  -- run it detached
    -- Now start Kong non-daemonized, but detached
    assert(pl_utils.execute(start_cmd))
    -- wait for Kong to be up and running, create a test service
    helpers.wait_until(function()
      local success, admin_client = pcall(helpers.admin_client)
      if not success then
        --print(admin_client)
        return false
      end
      local res = assert(admin_client:send {
        method = "POST",
        path = "/services",
        body = {
          name = "my-service",
          host = "127.0.0.1",
          port = helpers.test_conf.admin_listeners[1].port,
        },
        headers = {["Content-Type"] = "application/json"}
      })
      admin_client:close()
      --print(res.status)
      return res.status == 201
    end, 60)
    -- add a test route
    helpers.wait_until(function()
      local success, admin_client = pcall(helpers.admin_client)
      if not success then
        --print(admin_client)
        return false
      end
      local res = assert(admin_client:send {
        method = "POST",
        path = "/services/my-service/routes",
        body = {
          paths = { "/" },
        },
        headers = {["Content-Type"] = "application/json"}
      })
      admin_client:close()
      --print(res.status)
      return res.status == 201
    end, 10)
    -- make at least 1 succesful proxy request
    helpers.wait_until(function()
      -- make a request on the proxy port
      local proxy_client = helpers.proxy_client()
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/",
      })
      proxy_client:close()
      --print(res.status)
      return res.status == 200
    end, 10)
    -- fetch the log files we set
    local logout = assert(pl_utils.readfile(stdout))
    local logerr = assert(pl_utils.readfile(stderr))
    -- validate that the output contains the expected log messages
    assert(logerr:find("load_plugins(): Discovering used plugins", 1, true))
    assert(logout:find('"GET / HTTP/1.1" 200 ', 1, true))
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
      local _, _, stdout = assert(helpers.kong_exec("start --v --conf " .. helpers.test_conf_path))
      assert.matches("[verbose] prefix in use: ", stdout, nil, true)
    end)
    it("accepts debug --vv", function()
      local _, _, stdout = assert(helpers.kong_exec("start --vv --conf " .. helpers.test_conf_path))
      assert.matches("[verbose] prefix in use: ", stdout, nil, true)
      assert.matches("[debug] prefix = ", stdout, nil, true)
      assert.matches("[debug] database = ", stdout, nil, true)
    end)
    it("prints ENV variables when detected", function()
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

  describe("--run-migrations", function()
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
        pg_database = helpers.test_conf.pg_database
      }))

      local ok, stderr = helpers.kong_exec("stop --prefix inexistent")
      assert.False(ok)
      assert.matches("Error: no such prefix: .*/inexistent", stderr)
    end)
    it("notifies when Kong is already running", function()
      assert(helpers.kong_exec("start --prefix " .. helpers.test_conf.prefix, {
        pg_database = helpers.test_conf.pg_database
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
        pg_database = helpers.test_conf.pg_database
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
