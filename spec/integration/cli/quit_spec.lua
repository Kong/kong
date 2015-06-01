local spec_helper = require "spec.spec_helpers"

describe("CLI", function()

  setup(function()
    pcall(spec_helper.stop_kong)
  end)

  teardown(function()
    pcall(spec_helper.stop_kong)
  end)

  it("should not quit kong when it's not running", function()
    local ok = pcall(spec_helper.quit_kong)
    assert.falsy(ok)
  end)

  it("should quit kong when it's running", function()
    local _, code = spec_helper.start_kong()
    assert.are.same(0, code)
    local _, code = spec_helper.quit_kong()
    assert.are.same(0, code)
  end)

end)
