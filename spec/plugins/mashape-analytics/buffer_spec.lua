require "kong.tools.ngx_stub"

local ALFBuffer = require "kong.plugins.mashape-analytics.buffer"

local ALF_STUB = {}

describe("ALFBuffer", function()
  local alf_buffer

  it("should create a new buffer", function()
    alf_buffer = ALFBuffer.new()
    assert.truthy(alf_buffer)
  end)

  it("should be possible to add an ALF to it", function()
    local n = alf_buffer:add_alf(ALF_STUB)
    assert.equal(1, n)

    for i = 1, 100 do
      alf_buffer:add_alf(ALF_STUB)
    end

    assert.equal(101, #alf_buffer.alfs)
  end)

  it("should flush entries to the `to_send` buffer", function()
    alf_buffer:flush_entries()
    assert.equal(0, #alf_buffer.alfs)
    assert.equal(101, #alf_buffer.to_send)
  end)
end)
