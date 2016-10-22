local helpers = require "spec.helpers"

describe("kong quit", function()
  setup(function()
    helpers.prepare_prefix()
  end)
  after_each(function()
    helpers.kill_all()
  end)

  it("quit help", function()
    local _, stderr = helpers.kong_exec "quit --help"
    assert.not_equal("", stderr)
  end)
  it("quits gracefully", function()
    assert(helpers.kong_exec("start --conf " .. helpers.test_conf_path))
    helpers.wait_until_running(helpers.test_conf.nginx_pid)

    assert(helpers.kong_exec("quit --prefix " .. helpers.test_conf.prefix))
    assert(not helpers.kill.is_running(helpers.test_conf.nginx_pid))
  end)
  it("quit gracefully with --timeout option", function()
    assert(helpers.kong_exec("start --conf " .. helpers.test_conf_path))
    helpers.wait_until_running(helpers.test_conf.nginx_pid)

    assert(helpers.kong_exec("quit --timeout 2 --prefix " .. helpers.test_conf.prefix))
    assert(not helpers.kill.is_running(helpers.test_conf.nginx_pid))
  end)
end)
