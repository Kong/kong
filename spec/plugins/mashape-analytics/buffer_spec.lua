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

  it("should create a new buffer", function()
    local alf_buffer = ALFBuffer.new(CONF_STUB)
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
      local alf_buffer = ALFBuffer.new(CONF_STUB)
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
        local alf_buffer = ALFBuffer.new(CONF_STUB)
        alf_buffer:add_alf(ALF_STUB)

        -- Add 50 objects
        for i = 1, 50 do
          alf_buffer:add_alf(ALF_STUB)
        end

        local comma_size = string.len(",")
        local total_comma_size = 50 * comma_size -- 50 - 1 commas
        local braces_size = string.len("[]")
        local entries_size = alf_buffer.entries_size

        assert.equal(entries_size + total_comma_size + braces_size, alf_buffer:get_size())
      end)
    end)
  end)
  describe(":flush()", function()
    it("should have emptied the current buffer and added a payload to be sent", function()
      local alf_buffer = ALFBuffer.new(CONF_STUB)
      alf_buffer:add_alf(ALF_STUB)
      alf_buffer:flush()
      alf_buffer:add_alf(ALF_STUB)
      assert.equal(1, #alf_buffer.entries)
      assert.equal(1, #alf_buffer.sending_queue)
      assert.equal("table", type(alf_buffer.sending_queue[1]))
      assert.equal("string", type(alf_buffer.sending_queue[1].payload))
      assert.equal(STUB_LEN, alf_buffer.entries_size)
    end)
  end)
  describe("batch_size flushing", function()
    it("should call :flush() when reaching its n entries limit", function()
      local alf_buffer = ALFBuffer.new(CONF_STUB)

      spy.on(alf_buffer, "flush")
      finally(function()
        alf_buffer.flush:revert()
      end)

      for i = 1, 100 do
        alf_buffer:add_alf(ALF_STUB)
      end

      assert.spy(alf_buffer.flush).was_not.called()
      -- One more to go over the limit
      alf_buffer:add_alf(ALF_STUB)
      assert.spy(alf_buffer.flush).was.called()
      assert.equal(1, #alf_buffer.entries)
    end)
  end)
  describe("max collector payload size flushing", function()
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
  describe("max_queue_size", function()
    it("should discard a batch if the queue size has reached its configured limit", function()
      local COMMA_LEN = string.len(",")
      local JSON_ARR_LEN = string.len("[]")

      local n_stubs = 10000
      local batch_len = 100
      local n_batches = n_stubs/batch_len
      local batch_size = batch_len * (STUB_LEN + COMMA_LEN) + JSON_ARR_LEN - 1 -- no comma for last element of each batch
      local all_batches_size = (n_batches * batch_size) / MB

      local buffer_options = utils.table_merge(CONF_STUB, {batch_size = batch_len, sending_queue_size = all_batches_size})
      local buffer = ALFBuffer.new(buffer_options)

      spy.on(buffer, "flush")

      -- one more ALF to force the last flush, leaving us with 1 entries non-queued
      for i = 1, n_stubs + 1 do
        buffer:add_alf(ALF_STUB)
      end

      assert.spy(buffer.flush).was.called(n_batches)
      assert.equal(n_batches, #buffer.sending_queue) -- number batches pending for send
      assert.equal(1, #buffer.entries)

      -- now, if we force another flush, the sending queue is already full and should not accept a new batch
      for i = 1, batch_len do
        buffer:add_alf(ALF_STUB)
      end

      assert.spy(buffer.flush).was.called(n_batches + 1)
      assert.equal(1, #buffer.entries)
      assert.equal(n_batches, #buffer.sending_queue) -- same size as before

      -- repeat
      for i = 1, batch_len do
        buffer:add_alf(ALF_STUB)
      end

      assert.spy(buffer.flush).was.called(n_batches + 2)
      assert.equal(1, #buffer.entries)
      assert.equal(n_batches, #buffer.sending_queue) -- same size as before
    end)
  end)
end)
