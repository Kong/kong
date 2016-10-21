local helpers = require "spec.helpers"

describe("kong restart", function()
  setup(function()
    helpers.prepare_prefix()
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
    helpers.wait_until_running(helpers.test_conf.nginx_pid)
  end)
  it("restarts if already running from --conf", function()
    local env = {
      dnsmasq = true,
      dns_resolver = ""
    }

    assert(helpers.kong_exec("start --conf "..helpers.test_conf_path, env))
    helpers.wait_until_running(helpers.test_conf.nginx_pid)

    local serf_pid = assert(helpers.file.read(helpers.test_conf.serf_pid), "no serf pid")
    local nginx_pid = assert(helpers.file.read(helpers.test_conf.nginx_pid), "no nginx pid")
    local dnsmasq_pid = assert(helpers.file.read(helpers.test_conf.dnsmasq_pid), "no dnsmasq pid")

    assert(helpers.kong_exec("restart --conf "..helpers.test_conf_path, env))
    helpers.wait_until_running(helpers.test_conf.nginx_pid)

    assert.is_not.equal(assert(helpers.file.read(helpers.test_conf.nginx_pid)), nginx_pid)
    assert.is_not.equal(assert(helpers.file.read(helpers.test_conf.serf_pid)), serf_pid)
    assert.is_not.equal(assert(helpers.file.read(helpers.test_conf.dnsmasq_pid)), dnsmasq_pid)
  end)
  it("restarts if already running from --prefix", function()
    assert(helpers.kong_exec("start --conf "..helpers.test_conf_path, {
      dnsmasq = true,
      dns_resolver = ""
    }))
    helpers.wait_until_running(helpers.test_conf.nginx_pid)
    local serf_pid = assert(helpers.file.read(helpers.test_conf.serf_pid), "no serf pid")
    local nginx_pid = assert(helpers.file.read(helpers.test_conf.nginx_pid), "no nginx pid")
    local dnsmasq_pid = assert(helpers.file.read(helpers.test_conf.dnsmasq_pid), "no dnsmasq pid")

    assert(helpers.kong_exec("restart --prefix "..helpers.test_conf.prefix))
    helpers.wait_until_running(helpers.test_conf.nginx_pid)

    assert.is_not.equal(assert(helpers.file.read(helpers.test_conf.nginx_pid)), nginx_pid)
    assert.is_not.equal(assert(helpers.file.read(helpers.test_conf.serf_pid)), serf_pid)
    assert.is_not.equal(assert(helpers.file.read(helpers.test_conf.dnsmasq_pid)), dnsmasq_pid)
  end)
  it("accepts a custom nginx template", function()
    assert(helpers.kong_exec("start --conf "..helpers.test_conf_path))
    helpers.wait_until_running(helpers.test_conf.nginx_pid)

    assert(helpers.kong_exec(
      "restart --prefix " .. helpers.test_conf.prefix .. " " ..
      "--nginx-conf spec/fixtures/custom_nginx.template"
    ))
    helpers.wait_until_running(helpers.test_conf.nginx_pid)

    -- new server in this nginx config
    local client = helpers.http_client("0.0.0.0", 9999)
    local res = assert(client:send {
      path = "/custom_server_path"
    })
    assert.res_status(200, res)
    client:close()
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
