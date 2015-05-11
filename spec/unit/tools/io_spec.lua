local IO = require "kong.tools.io"
local spec_helper = require "spec.spec_helpers"

local TEST_FILE = "/tmp/test_file"

describe("IO", function()

  before_each(function()
    os.remove(TEST_FILE)
  end)

  it("should detect existing commands", function()
    assert.truthy(IO.cmd_exists("hash"))
    assert.falsy(IO.cmd_exists("hashasdasd"))
  end)

  it("should write and read from files", function()
    assert.truthy(IO.write_to_file(TEST_FILE, "this is a test"))
    assert.are.same("this is a test", IO.read_file(TEST_FILE))
  end)

  it("should detect existing files", function()
    assert.falsy(IO.file_exists(TEST_FILE))
    IO.write_to_file(TEST_FILE, "Test")
    assert.truthy(IO.cmd_exists(TEST_FILE))
  end)

  it("should execute an OS command", function()
    local res, code = IO.os_execute("echo \"Hello\"")
    assert.are.same(0, code)
    assert.truthy("Hello", res)

    local res, code = IO.os_execute("asdasda \"Hello\"")
    assert.are.same(127, code)
    assert.are.same("/bin/bash: asdasda: command not found", res)
  end)

  it("should check if a port is open", function()
    local PORT = 30000

    assert.falsy(IO.is_port_open(PORT))
    spec_helper.start_tcp_server(PORT, true, true)
    os.execute("sleep 0.5") -- Wait for the server to start
    assert.truthy(IO.is_port_open(PORT))
  end)

end)
