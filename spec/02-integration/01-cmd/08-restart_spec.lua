local helpers = require "spec.helpers"

describe("kong restart", function()
  setup(function()
    helpers.prepare_prefix()
  end)
  teardown(function()
    helpers.clean_prefix()
  end)
  after_each(function()
    helpers.kill_all()
  end)

  it("restart help", function()
    local _, stderr = helpers.kong_exec "restart --help"
    assert.not_equal("", stderr)
  end)
  it("restarts if not running", function()
    assert(helpers.kong_exec("restart --conf "..helpers.test_conf_path))
  end)
  it("restarts if already running from --conf", function()
    local env = {
      dnsmasq = true,
      dns_resolver = ""
    }

    assert(helpers.kong_exec("start --conf "..helpers.test_conf_path, env))
    local serf_pid = assert(helpers.file.read(helpers.test_conf.serf_pid))
    local nginx_pid = assert(helpers.file.read(helpers.test_conf.nginx_pid))
    local dnsmasq_pid = assert(helpers.file.read(helpers.test_conf.dnsmasq_pid))

    assert(helpers.kong_exec("restart --conf "..helpers.test_conf_path, env))
    assert.is_not.equal(assert(helpers.file.read(helpers.test_conf.nginx_pid)), nginx_pid)
    assert.is_not.equal(assert(helpers.file.read(helpers.test_conf.serf_pid)), serf_pid)
    assert.is_not.equal(assert(helpers.file.read(helpers.test_conf.dnsmasq_pid)), dnsmasq_pid)
  end)
  it("restarts if already running from --prefix", function()
    local env = {
      dnsmasq = true,
      dns_resolver = "",
      pg_database = helpers.test_conf.pg_database
    }

    assert(helpers.kong_exec("start --conf "..helpers.test_conf_path, env))
    local serf_pid = assert(helpers.file.read(helpers.test_conf.serf_pid))
    local nginx_pid = assert(helpers.file.read(helpers.test_conf.nginx_pid))
    local dnsmasq_pid = assert(helpers.file.read(helpers.test_conf.dnsmasq_pid))

    assert(helpers.kong_exec("restart --prefix "..helpers.test_conf.prefix, env))
    assert.is_not.equal(assert(helpers.file.read(helpers.test_conf.nginx_pid)), nginx_pid)
    assert.is_not.equal(assert(helpers.file.read(helpers.test_conf.serf_pid)), serf_pid)
    assert.is_not.equal(assert(helpers.file.read(helpers.test_conf.dnsmasq_pid)), dnsmasq_pid)
  end)
  pending("restarts with default configuration and prefix", function()
    -- don't want to force migrations to be run on default
    -- keyspace/database
    local env = {
      database = helpers.test_conf.database,
      pg_database = helpers.test_conf.pg_database,
      cassandra_keyspace = helpers.test_conf.cassandra_keyspace,
      dnsmasq = true,
      dns_resolver = ""
    }

    assert(helpers.kong_exec("start", env))
    assert(helpers.kong_exec("restart", env))
  end)
end)
