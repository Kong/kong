local spec_helper = require "spec.spec_helpers"
local constants = require "kong.constants"
local stringy = require "stringy"
local IO = require "kong.tools.io"

describe("CLI", function()

  setup(function()
    pcall(spec_helper.stop_kong)
  end)

  teardown(function()
    pcall(spec_helper.stop_kong)
  end)

  it("should restart kong when it's not running", function()
    local res, code = spec_helper.restart_kong()
    assert.are.same(0, code)
  end)

  it("should restart kong when it's running", function()
    local res, code = spec_helper.stop_kong()
    assert.are.same(0, code)
    local res, code = spec_helper.start_kong()
    assert.are.same(0, code)
    local res, code = spec_helper.restart_kong()
    assert.are.same(0, code)
  end)

  it("should restart kong when it's crashed", function()
    os.execute("pkill -9 nginx")
    local res, code = spec_helper.restart_kong()
    assert.are.same(0, code)
    assert.truthy(res:match("It seems like Kong crashed the last time it was started"))
  end)

end)
