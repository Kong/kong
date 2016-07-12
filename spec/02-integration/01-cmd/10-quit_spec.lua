local helpers = require "spec.helpers"

describe("kong start/stop", function()
  teardown(function()
    helpers.kill_all()
    helpers.clean_prefix()
  end)
  before_each(function()
    helpers.kill_all()
  end)

  it("quit help", function()
    local _, stderr = helpers.kong_exec "quit --help"
    assert.not_equal("", stderr)
  end)
  it("quits gracefully", function()
    assert(helpers.kong_exec("start --conf "..helpers.test_conf_path))
    assert(helpers.kong_exec("quit --prefix "..helpers.test_conf.prefix))
  end)

end)
