local helpers = require "spec.helpers"

local KILL_ALL = "pkill nginx; pkill serf; pkill dnsmasq"

local function exec(args, env)
  args = args or ""
  env = env or {}

  local env_vars = ""
  for k, v in pairs(env) do
    env_vars = string.format("%s KONG_%s=%s", env_vars, k:upper(), v)
  end
  return helpers.execute(env_vars.." "..helpers.bin_path.." "..args)
end

describe("kong start/stop", function()
  setup(function()
    helpers.execute(KILL_ALL)
    helpers.prepare_prefix()
  end)
  teardown(function()
    helpers.execute(KILL_ALL)
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
    local _, _, stdout, stderr = exec "start"
    assert.equal("", stderr)
    assert.not_equal("", stdout)

    ok, _, stdout, stderr = exec "stop"
    assert.not_equal("", stdout)
    assert.equal("", stderr)
    assert.True(ok)
  end)
  it("start/stop custom Kong conf/prefix", function()
    local _, _, stdout, stderr = exec("start --conf "..helpers.test_conf_path)
    assert.equal("", stderr)
    assert.not_equal("", stdout)

    _, _, stdout, stderr = exec("stop --conf "..helpers.test_conf_path)
    assert.equal("", stderr)
    assert.not_equal("", stdout)
  end)
  it("start with inexistent prefix", function()
    finally(function()
      helpers.execute(KILL_ALL)
      pcall(helpers.dir.rmtree, "foobar")
    end)

    local _, _, stdout, stderr = exec "start --prefix foobar"
    assert.equal("", stderr)
    assert.not_equal("", stdout)
  end)
  it("start dump config in prefix", function()
    local _, _, stdout, stderr = exec("start --conf "..helpers.test_conf_path)
    assert.equal("", stderr)
    assert.not_equal("", stdout)

    local conf_path = helpers.path.join(helpers.test_conf.prefix, "kong.conf")
    assert.truthy(helpers.path.exists(conf_path))

    _, _, stdout, stderr = exec("stop --conf "..helpers.test_conf_path)
    assert.equal("", stderr)
    assert.not_equal("", stdout)
  end)

  describe("verbose args", function()
    it("accepts verbose --v", function()
      local _, _, stdout, stderr = exec("start --v --conf "..helpers.test_conf_path)
      assert.equal("", stderr)
      assert.matches("[verbose] prefix in use: ", stdout, nil, true)

      finally(function()
        helpers.execute(KILL_ALL)
      end)
    end)
    it("accepts debug --vv", function()
      finally(function()
        helpers.execute(KILL_ALL)
      end)

      local _, _, stdout, stderr = exec("start --vv --conf "..helpers.test_conf_path)
      assert.matches("[verbose] prefix in use: ", stdout, nil, true)
      assert.matches("[debug] prefix = ", stdout, nil, true)
      assert.matches("[debug] database = ", stdout, nil, true)
      assert.equal("", stderr)
    end)
    it("should start with an inexistent prefix", function()
      local ok, _, stdout, stderr = exec "start --prefix foobar"
      assert.True(ok)
      assert.not_equal("", stdout)
      assert.equal("", stderr)
      finally(function()
        helpers.execute(KILL_ALL)
        helpers.dir.rmtree("foobar")
      end)
    end)
  end)

  describe("Serf", function()
    it("starts Serf agent daemon", function()
      local _, _, _, stderr = exec("start --conf "..helpers.test_conf_path)
      assert.equal("", stderr)

      local serf_pid_path = helpers.path.join(helpers.test_conf.prefix, "pids", "serf.pid")
      local cmd = string.format("kill -0 `cat %s` >/dev/null 2>&1", serf_pid_path)
      local ok, code = helpers.execute(cmd)
      assert.True(ok)
      assert.equal(0, code)

      assert.True(exec("stop --conf "..helpers.test_conf_path))
    end)
    it("recovers from expired serf.pid file", function()
      local serf_pid_path = helpers.path.join(helpers.test_conf.prefix, "pids", "serf.pid")
      local _, _, _, stderr = helpers.execute("touch "..serf_pid_path) -- dumb pid
      assert.equal("", stderr)

      local _, _, _, stderr = exec("start --conf "..helpers.test_conf_path)
      assert.equal("", stderr)

      local cmd = string.format("kill -0 `cat %s` >/dev/null 2>&1", serf_pid_path)
      local ok, code = helpers.execute(cmd)
      assert.True(ok)
      assert.equal(0, code)

      assert.True(exec("stop --conf "..helpers.test_conf_path))
    end)
  end)

  describe("dnsmasq", function()
    it("starts dnsmasq daemon", function()
      local ok = exec("start --conf "..helpers.test_conf_path, {
        dnsmasq = true,
        dns_resolver = ""
      })
      assert.True(ok)

      local dnsmasq_pid_path = helpers.path.join(helpers.test_conf.prefix, "pids", "dnsmasq.pid")
      local cmd = string.format("kill -0 `cat %s` >/dev/null 2>&1", dnsmasq_pid_path)
      local ok, code = helpers.execute(cmd)
      assert.True(ok)
      assert.equal(0, code)

      assert.True(exec("stop --conf "..helpers.test_conf_path))
    end)
    it("recovers from expired dnsmasq.pid file", function()
      local dnsmasq_pid_path = helpers.path.join(helpers.test_conf.prefix, "pids", "dnsmasq.pid")
      local _, _, _, stderr = helpers.execute("touch "..dnsmasq_pid_path) -- dumb pid
      assert.equal("", stderr)

      assert.True(exec("start --conf "..helpers.test_conf_path, {
        dnsmasq = true,
        dns_resolver = ""
      }))
      local cmd = string.format("kill -0 `cat %s` >/dev/null 2>&1", dnsmasq_pid_path)
      local ok, code = helpers.execute(cmd)
      assert.True(ok)
      assert.equal(0, code)

      assert.True(exec("stop --conf "..helpers.test_conf_path))
    end)
  end)

  describe("errors", function()
    it("start inexistent Kong conf file", function()
      local _, _, stdout, stderr = exec "start --conf foobar.conf"
      assert.equal("", stdout)
      assert.is_string(stderr)
      assert.matches("Error: no file at: foobar.conf", stderr, nil, true)
    end)
    it("stop inexistent prefix", function()
      finally(function()
        helpers.execute(KILL_ALL)
        helpers.dir.rmtree(helpers.test_conf.prefix)
      end)

      assert(helpers.dir.makepath(helpers.test_conf.prefix))

      local ok, _, stdout, stderr = exec("start --prefix "..helpers.test_conf.prefix)
      assert.True(ok)
      assert.not_equal("", stdout)
      assert.equal("", stderr)

      ok, _, stdout, stderr = exec("stop --prefix inexistent --conf "..helpers.test_conf_path)
      assert.False(ok)
      assert.equal("", stdout)
      assert.matches("Error: could not get Nginx pid", stderr, nil, true)
    end)
    it("notifies when Nginx is already running", function()
      finally(function()
        helpers.execute(KILL_ALL)
        helpers.dir.rmtree(helpers.test_conf.prefix)
      end)

      assert(helpers.dir.makepath(helpers.test_conf.prefix))

      local ok, _, stdout, stderr = exec("start --prefix "..helpers.test_conf.prefix)
      assert.True(ok)
      assert.not_equal("", stdout)
      assert.equal("", stderr)

      local ok, _, stdout, stderr = exec("start --prefix "..helpers.test_conf.prefix)
      assert.False(ok)
      assert.equal("", stdout)
      assert.matches("Nginx is already running in", stderr)
    end)
  end)
end)
