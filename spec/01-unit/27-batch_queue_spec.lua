
local BatchQueue = require "kong.tools.batch_queue"
local helpers = require "spec.helpers"

describe("batch queue", function()

  it("observes the limit parameter", function()
    local count = 0
    local last
    local function process(entries)
      count = count + #entries
      last = entries[#entries]
      return true
    end

    local q = BatchQueue.new("batch-queue-unit-test", process, {max_queued_batches=2, batch_max_size=100, process_delay=0})

    q:add(1)
    q:flush()
    q:add(2)
    q:flush()
    q:add(3)
    q:flush()

    helpers.wait_until(function()
      ngx.sleep(.1)
      return #q.batch_queue == 0
    end, 1)

    assert.equal(2, count)
    assert.equal(3, last)
  end)
end)
