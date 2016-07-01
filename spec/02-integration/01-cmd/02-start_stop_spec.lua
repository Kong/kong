local helpers = require "spec.helpers"

describe("kong start/stop", function()
  teardown(function()
    helpers.kill_all()
    helpers.clean_prefix()
  end)
  before_each(function()
    helpers.kill_all()
  end)

  it("start help", function()
    local _, stderr = helpers.kong_exec "start --help"
    assert.not_equal("", stderr)
  end)
  it("stop help", function()
    local _, stderr = helpers.kong_exec "stop --help"
    assert.not_equal("", stderr)
  end)
  it("start/stop default conf/prefix", function()
    -- don't want to force migrations to be run on default
    -- keyspace/database
    assert(helpers.kong_exec "start", {
      database = helpers.test_conf.database,
      pg_database = helpers.test_conf.pg_database,
      cassandra_keyspace = helpers.test_conf.cassandra_keyspace
    })
    assert(helpers.kong_exec "stop")
  end)
  it("start/stop custom Kong conf/prefix", function()
    assert(helpers.kong_exec("start --conf "..helpers.test_conf_path))
    assert(helpers.kong_exec("stop --prefix "..helpers.test_conf.prefix))
  end)
  it("start with inexistent prefix", function()
    finally(function()
      pcall(helpers.dir.rmtree, "foobar")
    end)

    assert(helpers.kong_exec "start --prefix foobar")
  end)
  it("start dumps Kong config in prefix", function()
    assert(helpers.kong_exec("start --conf "..helpers.test_conf_path))
    assert.truthy(helpers.path.exists(helpers.test_conf.kong_conf))
  end)

  describe("verbose args", function()
    it("accepts verbose --v", function()
      local _, stderr, stdout = helpers.kong_exec("start --v --conf "..helpers.test_conf_path)
      assert.equal("", stderr)
      assert.matches("[verbose] prefix in use: ", stdout, nil, true)
    end)
    it("accepts debug --vv", function()
      local _, stderr, stdout = helpers.kong_exec("start --vv --conf "..helpers.test_conf_path)
      assert.matches("[verbose] prefix in use: ", stdout, nil, true)
      assert.matches("[debug] prefix = ", stdout, nil, true)
      assert.matches("[debug] database = ", stdout, nil, true)
      assert.equal("", stderr)
    end)
    it("should start with an inexistent prefix", function()
      finally(function()
        helpers.kill_all()
        pcall(helpers.dir.rmtree, "foobar")
      end)

      assert(helpers.kong_exec "start --prefix foobar")
      assert.truthy(helpers.path.exists("foobar"))
    end)
    it("prints ENV variables when detected", function()
      finally(function()
        helpers.execute "pkill nginx; pkill serf"
      end)

      local _, stderr, stdout = helpers.kong_exec("start --vv --conf "..helpers.test_conf_path, {
        database = "postgres",
        admin_listen = "127.0.0.1:8001"
      })
      assert.equal("", stderr)
      assert.matches('KONG_DATABASE ENV found with "postgres"', stdout, nil, true)
      assert.matches('KONG_ADMIN_LISTEN ENV found with "127.0.0.1:8001"', stdout, nil, true)
    end)
    it("prints config in alphabetical order", function()
      finally(function()
        helpers.kill_all()
      end)

      local _, stderr, stdout = helpers.kong_exec("start --vv --conf "..helpers.test_conf_path)
      assert.equal("", stderr)
      assert.matches("admin_listen.*anonymous_reports.*cassandra_ssl.*prefix.*", stdout)
    end)
    it("does not print sensitive settings in config", function()
      finally(function()
        helpers.kill_all()
      end)

      local _, stderr, stdout = helpers.kong_exec("start --vv --conf "..helpers.test_conf_path, {
        pg_password = "do not print",
        cassandra_password = "do not print",
        cluster_encrypt_key = "fHGfspTRljmzLsYDVEK1Rw=="
      })
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
  end)

  describe("dnsmasq", function()
    it("starts dnsmasq daemon", function()
      assert(helpers.kong_exec("start --conf "..helpers.test_conf_path, {
        dnsmasq = true,
        dns_resolver = ""
      }))

      local cmd = string.format("kill -0 `cat %s` >/dev/null 2>&1",
                                helpers.test_conf.dnsmasq_pid)
      local _, code = helpers.utils.executeex(cmd)
      assert.equal(0, code)
    end)
    it("recovers from expired dnsmasq.pid file", function()
      assert(helpers.execute("touch "..helpers.test_conf.serf_pid)) -- dumb pid
      assert(helpers.kong_exec("start --conf "..helpers.test_conf_path, {
        dnsmasq = true,
        dns_resolver = ""
      }))

      local cmd = string.format("kill -0 `cat %s` >/dev/null 2>&1",
                                helpers.test_conf.serf_pid)
      local _, code = helpers.utils.executeex(cmd)
      assert.equal(0, code)
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
      finally(function()
        pcall(helpers.dir.rmtree, helpers.test_conf.prefix)
      end)

      local ok, stderr = helpers.kong_exec("start --prefix "..helpers.test_conf.prefix)
      assert.equal("", stderr)
      assert.True(ok)

      ok, stderr = helpers.kong_exec("stop --prefix inexistent")
      assert.False(ok)
      assert.matches("Error: no such prefix: .*/inexistent", stderr)
    end)
    it("notifies when Nginx is already running", function()
      finally(function()
        pcall(helpers.dir.rmtree, helpers.test_conf.prefix)
      end)

      assert(helpers.dir.makepath(helpers.test_conf.prefix))

      local ok, stderr = helpers.kong_exec("start --prefix "..helpers.test_conf.prefix)
      assert.equal("", stderr)
      assert.True(ok)

      ok, stderr = helpers.kong_exec("start --prefix "..helpers.test_conf.prefix)
      assert.False(ok)
      assert.matches("Nginx is already running in", stderr)
    end)
  end)
end)
