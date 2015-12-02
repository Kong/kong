require "kong.tools.ngx_stub"

local json = require "cjson"
local utils = require "kong.tools.utils"
local ALFBuffer = require "kong.plugins.mashape-analytics.buffer"

local MB = 1024 * 1024
local ALF_STUB = {hello = "world"}
local STUB_LEN = string.len(json.encode(ALF_STUB))
local CONF_STUB = {
  batch_size = 100,
  delay = 2,
  host = "",
  port = "",
  path = "",
  sending_queue_size = 10
}

describe("ALFBuffer", function()
  local alf_buffer

  it("should create a new buffer", function()
    alf_buffer = ALFBuffer.new(CONF_STUB)
    assert.truthy(alf_buffer)
    assert.equal(100, alf_buffer.max_entries)
    assert.equal(2, alf_buffer.auto_flush_delay)
    assert.equal(10 * MB, alf_buffer.max_queue_size)
    assert.equal("", alf_buffer.host)
    assert.equal("", alf_buffer.port)
    assert.equal("", alf_buffer.path)
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
    describe("max collector payload size", function()
      local MAX_BUFFER_SIZE
      setup(function()
        -- reduce the max collector payload size to 1MB
        -- for testing purposes.
        MAX_BUFFER_SIZE = ALFBuffer.MAX_BUFFER_SIZE
        ALFBuffer.MAX_BUFFER_SIZE = 0.5 * MB
      end)
      teardown(function()
        ALFBuffer.MAX_BUFFER_SIZE = MAX_BUFFER_SIZE
      end)
      it("should call :flush() when reaching its max size", function()
        -- How many stubs to reach the limit?
        local COMMA_LEN = string.len(",")
        local JSON_ARR_LEN = string.len("[]")
        local max_n_stubs = math.ceil(ALFBuffer.MAX_BUFFER_SIZE / (STUB_LEN + COMMA_LEN)) -- + the comma after each ALF in the JSON payload

        -- Create a new buffer with a batch_size big enough so that it does not prevent us from testing this behavior
        local buffer_options = utils.table_merge(CONF_STUB, {batch_size = max_n_stubs + 100})
        local buffer = ALFBuffer.new(buffer_options)

        spy.on(buffer, "flush")
        finally(function()
          buffer.flush:revert()
        end)

        -- Add max_n_stubs - 1 entries
        for i = 1, max_n_stubs - 1 do
          buffer:add_alf(ALF_STUB)
        end

        assert.spy(buffer.flush).was_not_called()

        -- We should have `(max_n_stubs - 1) * (STUB_LEN + COMMA_LEN) + JSON_ARR_LEN - COMMA_LEN` because no comma for latest object`
        -- as our current buffer size.
        assert.equal((max_n_stubs - 1) * (STUB_LEN + COMMA_LEN) + JSON_ARR_LEN - COMMA_LEN, buffer:get_size())

        -- adding one more entry
        buffer:add_alf(ALF_STUB)
        assert.spy(buffer.flush).was.called(1)
      end)
      it("should drop an ALF if it is too big by itself", function()
        local str = string.rep(".", ALFBuffer.MAX_BUFFER_SIZE)
        local huge_alf = {foo = str}

        local buffer = ALFBuffer.new(CONF_STUB)

        buffer:add_alf(huge_alf)

        assert.equal(0, buffer.entries_size)
        assert.equal(0, #buffer.entries)
      end)
    end)
    describe(":flush()", function()
      it("should have emptied the current buffer and added a payload to be sent", function()
        assert.equal(1, #alf_buffer.entries)
        assert.equal(1, #alf_buffer.sending_queue)
        assert.equal("table", type(alf_buffer.sending_queue[1]))
        assert.equal("string", type(alf_buffer.sending_queue[1].payload))
        assert.equal(STUB_LEN, alf_buffer.entries_size)
      end)
    end)
  end)
end)
