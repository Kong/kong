local spec_helper = require "spec.spec_helpers"
local IO = require "kong.tools.io"

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
    if not kong_pid then
      -- we might be to quick, so wait and retry
      os.execute("sleep 1")
      kong_pid = IO.read_file(spec_helper.get_env().configuration.pid_file)
      if not kong_pid then error("Could not read Kong pid") end
    end
    
    os.execute("pkill -9 nginx")

    repeat
       -- Wait till it's really over
      local _, code = IO.os_execute("kill -0 "..kong_pid)
    until(code ~= 0)

    local res, code = spec_helper.restart_kong()
    assert.are.same(0, code)
    assert.truthy(res:match("It seems like Kong crashed the last time it was started"))
  end)

end)
