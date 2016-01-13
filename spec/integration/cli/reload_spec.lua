local spec_helper = require "spec.spec_helpers"

describe("CLI", function()

  setup(function()
    pcall(spec_helper.stop_kong)
    spec_helper.prepare_db()
  end)

  teardown(function()
    pcall(spec_helper.stop_kong)
  end)

  it("should not reload kong when it's not running", function()
    local ok = pcall(spec_helper.reload_kong)
    assert.falsy(ok)
  end)

  it("should reload kong when it's running", function()
    local _, code = spec_helper.start_kong()
    assert.are.same(0, code)
    local _, code = spec_helper.reload_kong()
    assert.are.same(0, code)
  end)

  it("should not reload kong when it's crashed", function()
    os.execute("pkill -9 nginx")
    local ok = pcall(spec_helper.reload_kong)
    assert.falsy(ok)
  end)

end)
