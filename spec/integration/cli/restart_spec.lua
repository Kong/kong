local IO = require "kong.tools.io"
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
    local kong_pid = IO.read_file(spec_helper.get_env().configuration.pid_file)
    os.execute("pkill -9 nginx")
    while os.execute("kill -0 "..kong_pid.." ") == 0 do
      -- Wait till it's really over
    end

    local res, code = spec_helper.restart_kong()
    assert.are.same(0, code)
    assert.truthy(res:match("It seems like Kong crashed the last time it was started"))
  end)

end)
