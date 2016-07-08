local helpers = require "spec.helpers"

describe("kong restart", function()
  before_each(function()
    helpers.kill_all()
  end)
  teardown(function()
    helpers.kill_all()
    helpers.clean_prefix()
  end)

  it("restart help", function()
    local _, stderr = helpers.kong_exec "health --help"
    assert.not_equal("", stderr)
  end)
  it("restarts if not running", function()
    assert(helpers.kong_exec("restart --conf "..helpers.test_conf_path))
  end)
  it("restarts if already running", function()
    assert(helpers.kong_exec("start --conf "..helpers.test_conf_path, {dnsmasq = true, dns_resolver = ""}))

    local nginx_pid = assert(helpers.file.read(helpers.test_conf.nginx_pid))
    local serf_pid = assert(helpers.file.read(helpers.test_conf.serf_pid))
    local dnsmasq_pid = assert(helpers.file.read(helpers.test_conf.dnsmasq_pid))

    assert(helpers.kong_exec("restart --trace --conf "..helpers.test_conf_path, {dnsmasq = true, dns_resolver = ""}))

    assert.is_not.equal(assert(helpers.file.read(helpers.test_conf.nginx_pid)), nginx_pid)
    assert.is_not.equal(assert(helpers.file.read(helpers.test_conf.serf_pid)), serf_pid)
    assert.is_not.equal(assert(helpers.file.read(helpers.test_conf.dnsmasq_pid)), dnsmasq_pid)
  end)
end)
