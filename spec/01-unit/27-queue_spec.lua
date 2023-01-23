local Queue = require "kong.tools.queue"
local helpers = require "spec.helpers"


describe("plugin queue", function()
  local old_log
  local log_messages

  before_each(function()
    old_log = ngx.log
    log_messages = ""
    ngx.log = function(level, message)
      log_messages = log_messages .. helpers.ngx_log_level_names[level] .. " " .. message .. "\n"
    end
  end)

  after_each(function()
    ngx.log = old_log
  end)

  it("does not batch messages when `max_batch_size` is 1", function()
    local process_count = 0
    local q = Queue.get(
      "test",
      function()
        process_count = process_count + 1
        return true
      end,
      { name = "no-batch", batch_max_size = 1, poll_time = 0.1 }
    )
    q:add("One")
    q:add("Two")
    q:drain()
    assert.equals(2, process_count)
  end)

  it("batches messages when `batch_max_size` is 2", function()
    local process_count = 0
    local batch_size = 0
    local first_entry, last_entry
    local q = Queue.get(
      "test",
      function(batch)
        if not first_entry then
          first_entry = batch[1]
        end
        last_entry = batch[#batch]
        process_count = process_count + 1
        batch_size = #batch
        return true
      end,
      {
        name = "batch",
        batch_max_size = 2,
        poll_time = 0.1,
        max_delay = 0.1,
      }
    )
    q:add("One")
    q:add("Two")
    q:add("Three")
    q:add("Four")
    q:add("Five")
    q:drain()
    assert.equals(3, process_count)
    assert.equals("One", first_entry)
    assert.equals("Five", last_entry)
  end)

  it("retries sending messages", function()
    local process_count = 0
    local entry
    local q = Queue.get(
      "test",
      function(batch)
        entry = batch[1]
        process_count = process_count + 1
        return process_count == 2
      end,
      {
        name = "retry",
        batch_max_size = 1,
        poll_time = 0.1,
        max_delay = 0.1,
      }
    )
    q:add("Hello")
    q:drain()
    assert.equal(2, process_count)
    assert.equal("Hello", entry)
  end)

  it("gives up sending after retrying", function()
    local q = Queue.get(
      "test",
      function()
        return false, "failed"
      end,
      {
        name = "retry-give-up",
        batch_max_size = 1,
        max_retry_time = 1,
        poll_time = 0.1,
        max_delay = 0.1,
      }
    )
    q:add("Hello")
    q:drain()
    assert.match_re(log_messages, 'ERR .*1 queue entries were lost')
  end)

  it("drops entries when queue reaches its capacity", function()
    local processed
    local q = Queue.get(
      "test",
      function(batch)
        processed = batch
        return true
      end,
      {
        name = "capacity-exceeded",
        batch_max_size = 2,
        capacity = 2,
        poll_time = 0.1,
        max_delay = 0.1,
      }
    )
    q:add("One")
    q:add("Two")
    q:add("Three")
    q:add("Four")
    q:add("Five")
    q:drain()
    assert.equal("Four", processed[1])
    assert.equal("Five", processed[2])
    assert.match_re(log_messages, "ERR .*queue full")
    q:add("Six")
    q:drain()
    assert.equal("Six", processed[1])
    assert.match_re(log_messages, "INFO .*queue resumed processing")
  end)

  it("drops entries when it reaches its string_capacity", function()
    local processed
    local q = Queue.get(
      "test",
      function(batch)
        processed = batch
        return batch[1] == "4444", "Not expected"
      end,
      {
        name = "string-capacity-exceeded",
        batch_max_size = 1,
        string_capacity = 6,
        max_retry_time = 1,
        poll_time = 0.1
      })
    q:add("1")
    q:add("22")
    q:add("333")
    q:add("4444")
    q:drain()
    assert.equal("4444", processed[1])
    assert.match_re(log_messages, "ERR .*string capacity exceeded, 3 queue entries were dropped")

    q:add("55555")
    q:drain()
    assert.equal("55555", processed[1])

    q:add("666666")
    q:drain()
    assert.equal("666666", processed[1])
  end)

  it("warns about improper string_capacity setting", function()
    local q = Queue.get(
      "test",
      function(batch)
        return true
      end,
      {
        name = "string-capacity-warnings",
        batch_max_size = 1,
        string_capacity = 1,
        poll_time = 0.1
      })

    q:add("23")
    assert.match_re(log_messages,
      [[ERR .*string to be queued is longer \(2 bytes\) than the queue's string_capacity \(1 bytes\)]])
    log_messages = ""

    q:add({ foo = "bar" })
    assert.match_re(log_messages,
      "ERR .*queuing non-string data to a queue that has queue.string_capacity set, capacity monitoring will not be correct")
  end)

  it("detects inconsistent queue parameters", function()
    local q1 = Queue.get(
      "test",
      function() return true end,
      {
        name = "inconsistent",
        batch_max_size = 1,
      }
    )
    local q2 = Queue.get(
      "test",
      function() return true end,
      {
        name = "inconsistent",
        batch_max_size = 2,
      }
    )
    q1:drain()
    q2:drain()
    assert.match_re(log_messages, "ERR .*inconsistent")
  end)

  it("time out when idle", function()
    local process_count = 0
    local function get_queue()
      return Queue.get(
        "test",
        function()
          process_count = process_count + 1
          return true
        end,
        {
          name = "idle-timeout",
          poll_time = 0.1,
          max_idle_time = 1,
        }
      )
    end
    local q = get_queue()
    q:add("Hello World")
    assert.is_truthy(Queue.exists("test", "idle-timeout"))
    helpers.wait_until(
      function()
        return not Queue.exists("test", "idle-timeout")
      end,
      10)
    q = get_queue()
    q:add("and some more")
    helpers.wait_until(
      function()
        return process_count == 2
      end,
      10)
  end)
end)
