local IO = require "kong.tools.io"

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

    local res, code = IO.os_execute("LC_ALL=\"C\";asdasda \"Hello\"")
    assert.are.same(127, code)
    assert.are.same("asdasda: command not found", res)
  end)

end)
