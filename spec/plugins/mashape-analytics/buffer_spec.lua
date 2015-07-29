require "kong.tools.ngx_stub"

local ALFBuffer = require "kong.plugins.mashape-analytics.buffer"
local json = require "cjson"

local ALF_STUB = {hello = "world"}
local CONF_STUB = {
  batch_size = 100,
  delay = 2
}
local str = json.encode(ALF_STUB)
local STUB_LEN = string.len(str)

describe("ALFBuffer", function()
  local alf_buffer

  it("should create a new buffer", function()
    alf_buffer = ALFBuffer.new(CONF_STUB)
    assert.truthy(alf_buffer)
    assert.equal(100, alf_buffer.MAX_ENTRIES)
    assert.equal(2, alf_buffer.AUTO_FLUSH_DELAY)
  end)

  describe(":add_alf()", function()
    it("should be possible to add an ALF to it", function()
      local buffer = ALFBuffer.new(CONF_STUB)
      buffer:add_alf(ALF_STUB)
      assert.equal(1, #buffer.entries)
    end)
    it("should compute and update the current buffer size in bytes", function()
      alf_buffer:add_alf(ALF_STUB)
      assert.equal(STUB_LEN, alf_buffer.entries_size)

      -- Add 50 objects
      for i = 1, 50 do
        alf_buffer:add_alf(ALF_STUB)
      end
      assert.equal(51 * STUB_LEN, alf_buffer.entries_size)
    end)
    describe(":get_size()", function()
      it("should return the hypothetical size of what the payload should be", function()
        local comma_size = string.len(",")
        local total_comma_size = 50 * comma_size -- 51 - 1 commas
        local braces_size = string.len("[]")
        local entries_size = alf_buffer.entries_size

        assert.equal(entries_size + total_comma_size + braces_size, alf_buffer:get_size())
      end)
    end)
    it("should call :flush() when reaching its n entries limit", function()
      local s = spy.on(alf_buffer, "flush")

      -- Add 49 more entries
      for i = 1, 49 do
        alf_buffer:add_alf(ALF_STUB)
      end

      assert.spy(s).was_not.called()
      -- One more to go over the limit
      alf_buffer:add_alf(ALF_STUB)
      assert.spy(s).was.called()

      finally(function()
        alf_buffer.flush:revert()
      end)
    end)
    describe(":flush()", function()
      it("should have emptied the current buffer and added a payload to be sent", function()
        assert.equal(1, #alf_buffer.entries)
        assert.equal(1, #alf_buffer.sending_queue)
        assert.equal("string", type(alf_buffer.sending_queue[1]))
        assert.equal(STUB_LEN, alf_buffer.entries_size)
      end)
    end)
  end)
end)
