local helpers = require "spec.helpers"

local function exec(args)
  args = args or ""
  return helpers.execute(helpers.bin_path.." "..args)
end

describe("kong start/stop", function()
  setup(function()
    helpers.execute "pkill nginx; pkill serf"
    helpers.prepare_prefix()
  end)
  teardown(function()
    helpers.execute "pkill nginx; pkill serf"
    helpers.clean_prefix()
  end)

  it("start help", function()
    local _, _, stdout, stderr = exec "start --help"
    assert.equal("", stdout)
    assert.is_string(stderr)
    assert.not_equal("", stderr)
  end)
  it("stop help", function()
    local _, _, stdout, stderr = exec "stop --help"
    assert.equal("", stdout)
    assert.is_string(stderr)
    assert.not_equal("", stderr)
  end)
  it("start/stop default conf/prefix", function()
    -- don't want to force migrations to be run on default
    -- keyspace/database
    local ok, _, stdout, stderr = exec "start"
    assert.not_equal("", stdout)
    assert.equal("", stderr)
    assert.True(ok)

    ok, _, stdout, stderr = exec "stop"
    assert.not_equal("", stdout)
    assert.equal("", stderr)
    assert.True(ok)
  end)
  it("start/stop custom Kong conf/prefix", function()
    local ok, _, stdout, stderr = exec("start --conf "..helpers.test_conf_path)
    assert.True(ok)
    assert.not_equal("", stdout)
    assert.equal("", stderr)

    ok, _, stdout, stderr = exec("stop --prefix "..helpers.test_conf.prefix)
    assert.True(ok)
    assert.not_equal("", stdout)
    assert.equal("", stderr)
  end)

  describe("verbose args", function()
    it("accepts verbose", function()
      local ok, _, stdout, stderr = exec("start --v --conf "..helpers.test_conf_path)
      assert.True(ok)
      assert.matches("[verbose] prefix in use: ", stdout, nil, true)
      assert.equal("", stderr)

      finally(function()
        helpers.execute "pkill nginx; pkill serf"
      end)
    end)
    it("accepts debug", function()
      local ok, _, stdout, stderr = exec("start --vv --conf "..helpers.test_conf_path)
      assert.True(ok)
      assert.matches("[verbose] prefix in use: ", stdout, nil, true)
      assert.matches("[debug] prefix = ", stdout, nil, true)
      assert.matches("[debug] database = ", stdout, nil, true)
      assert.equal("", stderr)

      finally(function()
        helpers.execute "pkill nginx; pkill serf"
      end)
    end)
    it("prints ENV variables when detected", function()
      finally(function()
        helpers.execute "pkill nginx; pkill serf"
      end)

      local ENV = "KONG_DATABASE=postgres KONG_ADMIN_LISTEN=127.0.0.1:8001"
      local _, _, stdout, stderr = helpers.execute(ENV.." bin/kong start --vv --conf "..helpers.test_conf_path)
      assert.equal("", stderr)
      assert.matches('KONG_DATABASE ENV found with "postgres"', stdout, nil, true)
      assert.matches('KONG_ADMIN_LISTEN ENV found with "127.0.0.1:8001"', stdout, nil, true)
    end)
    it("prints config in alphabetical order", function()
      finally(function()
        helpers.execute "pkill nginx; pkill serf"
      end)

      local _, _, stdout, stderr = exec("start --vv --conf "..helpers.test_conf_path)
      assert.equal("", stderr)
      assert.matches("admin_listen.*anonymous_reports.*cassandra_ssl.*prefix.*", stdout)
    end)
    it("does not print sensitive settings in config", function()
      finally(function()
        helpers.execute "pkill nginx; pkill serf"
      end)

      local ENV = "KONG_PG_PASSWORD='do not print' KONG_CASSANDRA_PASSWORD='do not print'"
                .." KONG_CLUSTER_ENCRYPT_KEY=fHGfspTRljmzLsYDVEK1Rw=="
      local _, _, stdout, stderr = helpers.execute(ENV.." bin/kong start --vv --conf "..helpers.test_conf_path)
      assert.equal("", stderr)
      assert.matches('KONG_PG_PASSWORD ENV found with "******"', stdout, nil, true)
      assert.matches('KONG_CASSANDRA_PASSWORD ENV found with "******"', stdout, nil, true)
      assert.matches('KONG_CLUSTER_ENCRYPT_KEY ENV found with "******"', stdout, nil, true)
      assert.matches('pg_password = "******"', stdout, nil, true)
      assert.matches('cassandra_password = "******"', stdout, nil, true)
      assert.matches('cluster_encrypt_key = "******"', stdout, nil, true)
    end)
  end)

  describe("Serf", function()
    it("starts Serf agent daemon", function()
      local ok = exec("start --conf "..helpers.test_conf_path)
      assert.True(ok)

      local serf_pid_path = helpers.path.join(helpers.test_conf.prefix, "serf.pid")
      local cmd = string.format("kill -0 `cat %s` >/dev/null 2>&1", serf_pid_path)
      local ok, code = helpers.execute(cmd)
      assert.True(ok)
      assert.equal(0, code)

      assert.True(exec("stop --prefix "..helpers.test_conf.prefix))
    end)
    it("recovers from expired serf.pid file", function()
      local serf_pid_path = helpers.path.join(helpers.test_conf.prefix, "serf.pid")
      local ok = helpers.execute("touch "..serf_pid_path) -- dumb pid
      assert.True(ok)

      assert.True(exec("start --conf "..helpers.test_conf_path))

      local cmd = string.format("kill -0 `cat %s` >/dev/null 2>&1", serf_pid_path)
      local ok, code = helpers.execute(cmd)
      assert.True(ok)
      assert.equal(0, code)

      assert.True(exec("stop --prefix "..helpers.test_conf.prefix))
    end)
  end)

  describe("errors", function()
    it("start inexistent Kong conf file", function()
      local ok, _, stdout, stderr = exec "start --conf foobar.conf"
      assert.False(ok)
      assert.equal("", stdout)
      assert.is_string(stderr)
      assert.matches("Error: no file at: foobar.conf", stderr, nil, true)
    end)
    it("start inexistent prefix", function()
      local ok, _, stdout, stderr = exec "start --prefix foobar"
      assert.False(ok)
      assert.equal("", stdout)
      assert.matches("foobar does not exist", stderr, nil, true)
    end)
    it("stop inexistent prefix", function()
      assert(helpers.dir.makepath(helpers.test_conf.prefix))

      local ok, _, stdout, stderr = exec("start --prefix "..helpers.test_conf.prefix)
      assert.True(ok)
      assert.not_equal("", stdout)
      assert.equal("", stderr)

      ok, _, stdout, stderr = exec "stop --prefix inexistent"
      assert.False(ok)
      assert.equal("", stdout)
      assert.matches("Error: could not get Nginx pid", stderr, nil, true)

      finally(function()
        helpers.execute "pkill nginx; pkill serf"
        helpers.dir.rmtree(helpers.test_conf.prefix)
      end)
    end)
    it("notifies when Nginx is already running", function()
      assert(helpers.dir.makepath(helpers.test_conf.prefix))

      local ok, _, stdout, stderr = exec("start --prefix "..helpers.test_conf.prefix)
      assert.True(ok)
      assert.not_equal("", stdout)
      assert.equal("", stderr)

      local ok, _, stdout, stderr = exec("start --prefix "..helpers.test_conf.prefix)
      assert.False(ok)
      assert.equal("", stdout)
      assert.matches("Nginx is already running in", stderr)
      finally(function()
        helpers.execute "pkill nginx; pkill serf"
        helpers.dir.rmtree(helpers.test_conf.prefix)
      end)
    end)
  end)
end)
