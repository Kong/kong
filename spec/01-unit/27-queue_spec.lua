local Queue = require "kong.tools.queue"
local helpers = require "spec.helpers"
local timerng = require "resty.timerng"
local queue_schema = require "kong.tools.queue_schema"

local function queue_conf(conf)
  local defaulted_conf = {}
  for _, field in ipairs(queue_schema.fields) do
    for name, attrs in pairs(field) do
      defaulted_conf[name] = conf[name] or attrs.default
    end
  end
  return defaulted_conf
end


describe("plugin queue", function()
  local old_log
  local log_messages

  lazy_setup(function()
    kong.timer = timerng.new()
    kong.timer:start()
  end)

  lazy_teardown(function()
    kong.timer:destroy()
  end)

  before_each(function()
    old_log = ngx.log
    log_messages = ""
    ngx.log = function(level, message) -- luacheck: ignore
      log_messages = log_messages .. helpers.ngx_log_level_names[level] .. " " .. message .. "\n"
    end
  end)

  after_each(function()
    ngx.log = old_log -- luacheck: ignore
  end)

  it("passes configuration to handler", function ()
    local handler_invoked = 0
    local configuration_sent = { foo = "bar" }
    local configuration_received
    Queue.enqueue(
      queue_conf({ name = "handler-configuration" }),
      function (conf)
        handler_invoked = handler_invoked + 1
        configuration_received = conf
        return true
      end,
      configuration_sent,
      "ENTRY"
    )
    Queue.drain("handler-configuration")
    helpers.wait_until(
      function ()
        return handler_invoked == 1
      end,
      1)
    assert.equals(configuration_sent, configuration_received)
  end)

  it("configuration changes are observed for older entries", function ()
    local handler_invoked = 0
    local first_configuration_sent = { foo = "bar" }
    local second_configuration_sent = { foo = "bar" }
    local configuration_received
    local number_of_entries_received
    local function enqueue(conf, entry)
      Queue.enqueue(
        queue_conf({
          name = "handler-configuration-change",
          batch_max_size = 10,
          max_delay = 0.1
        }),
        function (c, entries)
          handler_invoked = handler_invoked + 1
          configuration_received = c
          number_of_entries_received = #entries
          return true
        end,
        conf,
        entry
      )
    end
    enqueue(first_configuration_sent, "ENTRY1")
    enqueue(second_configuration_sent, "ENTRY2")
    Queue.drain("handler-configuration-change")
    helpers.wait_until(
      function ()
        return handler_invoked == 1
      end,
      1)
    assert.equals(configuration_received, second_configuration_sent)
    assert.equals(2, number_of_entries_received)
  end)

  it("does not batch messages when `batch_max_size` is 1", function()
    local process_count = 0
    local function enqueue(entry)
      Queue.enqueue(
        queue_conf({ name = "no-batch", batch_max_size = 1 }),
        function()
          process_count = process_count + 1
          return true
        end,
        nil,
        entry
      )
    end
    enqueue("One")
    enqueue("Two")
    Queue.drain("no-batch")
    assert.equals(2, process_count)
  end)

  it("batches messages when `batch_max_size` is 2", function()
    local process_count = 0
    local first_entry, last_entry
    local function enqueue(entry)
      Queue.enqueue(
        queue_conf({
          name = "batch",
          batch_max_size = 2,
          max_delay = 0.1,
        }),
        function(_, batch)
          if not first_entry then
            first_entry = batch[1]
          end
          last_entry = batch[#batch]
          process_count = process_count + 1
          return true
        end,
        nil,
        entry
      )
    end
    enqueue("One")
    enqueue("Two")
    enqueue("Three")
    enqueue("Four")
    enqueue("Five")
    Queue.drain("batch")
    assert.equals(3, process_count)
    assert.equals("One", first_entry)
    assert.equals("Five", last_entry)
  end)

  it("retries sending messages", function()
    local process_count = 0
    local entry
    Queue.enqueue(
      queue_conf({
        name = "retry",
        batch_max_size = 1,
        max_delay = 0.1,
      }),
      function(_, batch)
        entry = batch[1]
        process_count = process_count + 1
        return process_count == 2
      end,
      nil,
      "Hello"
    )
    Queue.drain("retry")
    assert.equal(2, process_count)
    assert.equal("Hello", entry)
  end)

  it("gives up sending after retrying", function()
    Queue.enqueue(
      queue_conf({
        name = "retry-give-up",
        batch_max_size = 1,
        max_retry_time = 1,
        max_delay = 0.1,
      }),
      function()
        return false, "failed"
      end,
      nil,
      "Hello"
    )
    Queue.drain("retry-give-up")
    assert.match_re(log_messages, 'ERR .*1 queue entries were lost')
  end)

  it("drops entries when queue reaches its capacity", function()
    local processed
    local function enqueue(entry)
      Queue.enqueue(
        queue_conf({
          name = "capacity-exceeded",
          batch_max_size = 2,
          capacity = 2,
          max_delay = 0.1,
        }),
        function(_, batch)
          processed = batch
          return true
        end,
        nil,
        entry
      )
    end
    enqueue("One")
    enqueue("Two")
    enqueue("Three")
    enqueue("Four")
    enqueue("Five")
    Queue.drain("capacity-exceeded")
    assert.equal("Four", processed[1])
    assert.equal("Five", processed[2])
    assert.match_re(log_messages, "ERR .*queue full")
    enqueue("Six")
    Queue.drain("capacity-exceeded")
    assert.equal("Six", processed[1])
    assert.match_re(log_messages, "INFO .*queue resumed processing")
  end)

  it("drops entries when it reaches its string_capacity", function()
    local processed
    local function enqueue(entry)
      Queue.enqueue(
        queue_conf({
          name = "string-capacity-exceeded",
          batch_max_size = 1,
          string_capacity = 6,
          max_retry_time = 1,
        }),
        function(_, entries)
          processed = entries
          return true
        end,
        nil,
        entry
      )
    end
    enqueue("1")
    enqueue("22")
    enqueue("333")
    enqueue("4444")
    Queue.drain("string-capacity-exceeded")
    assert.equal("4444", processed[1])
    assert.match_re(log_messages, "ERR .*string capacity exceeded, 3 queue entries were dropped")

    enqueue("55555")
    Queue.drain("string-capacity-exceeded")
    assert.equal("55555", processed[1])

    enqueue("666666")
    Queue.drain("string-capacity-exceeded")
    assert.equal("666666", processed[1])
  end)

  it("warns about improper string_capacity setting", function()
    local function enqueue(entry)
      Queue.enqueue(
        queue_conf({
          name = "string-capacity-warnings",
          batch_max_size = 1,
          string_capacity = 1,
        }),
        function ()
          return true
        end,
        nil,
        entry
      )
    end

    enqueue("23")
    assert.match_re(log_messages,
      [[ERR .*string to be queued is longer \(2 bytes\) than the queue's string_capacity \(1 bytes\)]])
    log_messages = ""

    enqueue({ foo = "bar" })
    assert.match_re(log_messages,
      "ERR .*queuing non-string entry to a queue that has queue.string_capacity set, capacity monitoring will not be correct")
  end)

  it("queue is deleted when it is done sending", function()
    local process_count = 0
    local function enqueue(entry)
      Queue.enqueue(
        queue_conf({ name = "no-garbage" }),
        function()
          process_count = process_count + 1
          return true
        end,
        nil,
        entry
      )
    end
    enqueue("Hello World")
    assert.is_truthy(Queue.exists("no-garbage"))
    helpers.wait_until(
      function()
        return not Queue.exists("no-garbage")
      end,
      10)
    enqueue("and some more")
    helpers.wait_until(
      function()
        return process_count == 2
      end,
      10)
  end)

  it("sends data quickly", function()
    local entry_count = 1000
    local last
    for i = 1,entry_count do
      Queue.enqueue(
        queue_conf({
          name = "speedy-sending",
          batch_max_size = 10,
          max_delay = 0.1,
        }),
        function(conf, entries)
          last = entries[#entries]
          return true
        end,
        nil,
        i
      )
    end
    helpers.wait_until(
      function ()
        return last == entry_count
      end,
      1
    )
  end)

  it("converts common legacy queue parameters", function()
    local legacy_parameters = {
      retry_count = 123,
      queue_size = 234,
      flush_timeout = 345,
    }
    local converted_parameters = Queue.get_params(legacy_parameters)
    assert.match_re(log_messages, 'deprecated `retry_count` parameter in plugin .* ignored')
    assert.equals(legacy_parameters.queue_size, converted_parameters.batch_max_size)
    assert.match_re(log_messages, 'deprecated `queue_size` parameter in plugin .* converted to `queue.batch_max_size`')
    assert.equals(legacy_parameters.flush_timeout, converted_parameters.max_delay)
    assert.match_re(log_messages, 'deprecated `flush_timeout` parameter in plugin .* converted to `queue.max_delay`')
  end)

  it("converts opentelemetry plugin legacy queue parameters", function()
    local legacy_parameters = {
      batch_span_count = 234,
      batch_flush_delay = 345,
    }
    local converted_parameters = Queue.get_params(legacy_parameters)
    assert.equals(legacy_parameters.batch_span_count, converted_parameters.batch_max_size)
    assert.match_re(log_messages, 'deprecated `batch_span_count` parameter in plugin .* converted to `queue.batch_max_size`')
    assert.equals(legacy_parameters.batch_flush_delay, converted_parameters.max_delay)
    assert.match_re(log_messages, 'deprecated `batch_flush_delay` parameter in plugin .* converted to `queue.max_delay`')
  end)

  it("defaulted legacy parameters are ignored when converting", function()
    local legacy_parameters = {
      queue_size = 1,
      flush_timeout = 2,
      batch_span_count = 200,
      batch_flush_delay = 3,
      queue = {
        batch_max_size = 123,
        max_delay = 234,
      }
    }
    local converted_parameters = Queue.get_params(legacy_parameters)
    assert.equals(123, converted_parameters.batch_max_size)
    assert.equals(234, converted_parameters.max_delay)
  end)
end)
