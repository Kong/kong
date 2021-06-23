local message = require("kong.hybrid.message")


describe("kong.hybrid.message", function()
  describe(".new()", function()
    it("happy path", function()
      local m = message.new("1c8db62c-7221-47d6-9090-3593851f21cb", "control_plane", "test_topic", "test_message")
      assert.is_table(m)
      assert.equal("1c8db62c-7221-47d6-9090-3593851f21cb", m.src)
      assert.equal("control_plane", m.dest)
      assert.equal("test_topic", m.topic)
      assert.equal("test_message", m.message)
    end)

    it("src is nil", function()
      local m = message.new(nil, "control_plane", "test_topic", "test_message")
      assert.is_table(m)
      assert.equal(nil, m.src)
      assert.equal("control_plane", m.dest)
      assert.equal("test_topic", m.topic)
      assert.equal("test_message", m.message)
    end)

    describe("checks for field size", function()
      it("src", function()
        local m = message.new(string.rep("a", 255), "control_plane", "test_topic", "test_message")
        assert.is_table(m)
        assert.equal(string.rep("a", 255), m.src)
        assert.equal("control_plane", m.dest)
        assert.equal("test_topic", m.topic)
        assert.equal("test_message", m.message)

        assert.has_error(function()
          message.new(string.rep("a", 256), "control_plane", "test_topic", "test_message")
        end)
      end)

      it("dest", function()
        local m = message.new("1c8db62c-7221-47d6-9090-3593851f21cb", string.rep("a", 255), "test_topic", "test_message")
        assert.is_table(m)
        assert.equal("1c8db62c-7221-47d6-9090-3593851f21cb", m.src)
        assert.equal(string.rep("a", 255), m.dest)
        assert.equal("test_topic", m.topic)
        assert.equal("test_message", m.message)

        assert.has_error(function()
          message.new("1c8db62c-7221-47d6-9090-3593851f21cb", string.rep("a", 256), "test_topic", "test_message")
        end)
      end)

      it("topic", function()
        local m = message.new("1c8db62c-7221-47d6-9090-3593851f21cb", "control_plane", string.rep("a", 255), "test_message")
        assert.is_table(m)
        assert.equal("1c8db62c-7221-47d6-9090-3593851f21cb", m.src)
        assert.equal("control_plane", m.dest)
        assert.equal(string.rep("a", 255), m.topic)
        assert.equal("test_message", m.message)

        assert.has_error(function()
          message.new("1c8db62c-7221-47d6-9090-3593851f21cb", "control_plane", string.rep("a", 256), "test_message")
        end)
      end)

      it("message", function()
        local m = message.new("1c8db62c-7221-47d6-9090-3593851f21cb", "control_plane", "test_topic", string.rep("a", 64 * 1024 * 1024 - 1))
        assert.is_table(m)
        assert.equal("1c8db62c-7221-47d6-9090-3593851f21cb", m.src)
        assert.equal("control_plane", m.dest)
        assert.equal("test_topic", m.topic)
        assert.equal(string.rep("a", 64 * 1024 * 1024 - 1), m.message)

        assert.has_error(function()
          message.new("1c8db62c-7221-47d6-9090-3593851f21cb", "control_plane", "test_topic", string.rep("a", 64 * 1024 * 1024))
        end)
      end)
    end)
  end)

  it("has the correct metatable", function()
    local m = message.new("1c8db62c-7221-47d6-9090-3593851f21cb", "control_plane", "test_topic", "test_message")
    assert.is_table(getmetatable(m))
    assert.is_table(getmetatable(m).__index)
  end)

  it(":pack()", function()
    local m = message.new("1c8db62c-7221-47d6-9090-3593851f21cb", "control_plane", "test_topic", "test_message")

    local packed = m:pack()
    assert.equal("\x241c8db62c-7221-47d6-9090-3593851f21cb\x0dcontrol_plane\x0atest_topic\x00\x00\x00\x0ctest_message", packed)
  end)

  it(":unpack()", function()
    local ptr = 1
    local packed = "\x241c8db62c-7221-47d6-9090-3593851f21cb\x0dcontrol_plane\x0atest_topic\x00\x00\x00\x0ctest_message"

    local fake_sock = {
      receive = function(self, size)
        local s = packed:sub(ptr, ptr + size - 1)
        ptr = ptr + size

        return s
      end,
    }
    local m = message.unpack_from_socket(fake_sock)

    assert.is_table(m)
    assert.equal("1c8db62c-7221-47d6-9090-3593851f21cb", m.src)
    assert.equal("control_plane", m.dest)
    assert.equal("test_topic", m.topic)
    assert.equal("test_message", m.message)
  end)
end)
