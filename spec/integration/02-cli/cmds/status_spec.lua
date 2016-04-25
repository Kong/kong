local spec_helper = require "spec.spec_helpers"

describe("CLI", function()

  setup(function()
    pcall(spec_helper.stop_kong)
  end)

  teardown(function()
    pcall(spec_helper.stop_kong)
  end)

  it("the status check should fail when Kong is not running", function()
    assert.error_matches(function()
      spec_helper.status_kong()
    end, "Kong is not running", nil, true)
  end)

  it("the status check should not fail when Kong is running", function()
    local _, code = spec_helper.start_kong()
    assert.are.same(0, code)
    local ok = pcall(spec_helper.status_kong)
    assert.truthy(ok)
    local ok = pcall(spec_helper.stop_kong)
    assert.truthy(ok)
  end)

  it("the status check should fail when some services are not running", function()
    local _, code = spec_helper.start_kong()
    assert.are.same(0, code)

    os.execute("pkill serf")

    assert.error_matches(function()
      spec_helper.status_kong()
    end, "Some services required by Kong are not running. Please execute \"kong restart\"!", nil, true)
  end)


end)
