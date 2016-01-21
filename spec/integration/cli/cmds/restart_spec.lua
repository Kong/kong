local spec_helper = require "spec.spec_helpers"

describe("CLI", function()

  setup(function()
    pcall(spec_helper.stop_kong)
  end)

  teardown(function()
    pcall(spec_helper.stop_kong)
  end)

  it("should restart kong when it's not running", function()
    local _, code = spec_helper.restart_kong()
    assert.are.same(0, code)
  end)

  it("should restart kong when it's running", function()
    local _, code = spec_helper.stop_kong()
    assert.are.same(0, code)
    _, code = spec_helper.start_kong()
    assert.are.same(0, code)
    _, code = spec_helper.restart_kong()
    assert.are.same(0, code)
  end)

  it("should restart kong when it's crashed", function()
    os.execute("pkill -9 nginx")
    local _, code = spec_helper.restart_kong()
    assert.are.same(0, code)
  end)

  it("should restart when a service has crashed", function()
    os.execute("pkill -9 serf")
    local _, code = spec_helper.restart_kong()
    assert.are.same(0, code)
  end)

end)