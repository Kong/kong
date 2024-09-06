local Queue = require "kong.tools.queue"
local cycle_aware_deep_copy = require("kong.tools.table").cycle_aware_deep_copy
local helpers = require "spec.helpers"
local mocker = require "spec.fixtures.mocker"
local timerng = require "resty.timerng"
local queue_schema = require "kong.tools.queue_schema"
local uuid = require("kong.tools.uuid").uuid
local queue_num = 1


local function queue_conf(conf)
  local defaulted_conf = cycle_aware_deep_copy(conf)
  if not conf.name then
    defaulted_conf.name = "test-" .. tostring(queue_num)
    queue_num = queue_num + 1
  end
  for _, field in ipairs(queue_schema.fields) do
    for name, attrs in pairs(field) do
      defaulted_conf[name] = conf[name] or attrs.default
    end
  end
  return defaulted_conf
end


local function wait_until_queue_done(name)
  helpers.wait_until(function()
    return not Queue._exists(name)
  end, 10)
end

describe("plugin queue", function()

  lazy_setup(function()
    kong.timer = timerng.new()
    kong.timer:start()
    -- make sure our workspace is explicitly set so that we test behavior in the presence of workspaces
    ngx.ctx.workspace = "queue-tests"
  end)

  lazy_teardown(function()
    kong.timer:destroy()
    ngx.ctx.workspace = nil
  end)

  local unmock
  local now_offset
  local log_messages

  local function count_matching_log_messages(s)
    return select(2, string.gsub(log_messages, s, ""))
  end

  before_each(function()
    local real_now = ngx.now
    now_offset = 0

    log_messages = ""
    local function log(level, message) -- luacheck: ignore
      log_messages = log_messages .. level .. " " .. message .. "\n"
    end

    mocker.setup(function(f)
      unmock = f
    end, {
      kong = {
        log = {
          debug = function(message) return log('DEBUG', message) end,
          info = function(message) return log('INFO', message) end,
          warn = function(message) return log('WARN', message) end,
          err = function(message) return log('ERR', message) end,
        },
        plugin = {
          get_id = function () return uuid() end,
        },
      },
      ngx = {
        ctx = {
          -- make sure our workspace is nil to begin with to prevent leakage from
          -- other tests
          workspace = nil
        },
        -- We want to be able to fake the time returned by ngx.now() only in the queue module and leave everything
        -- else alone so that we can see what effects changing the system time has on queues.
        now = function()
          local called_from = debug.getinfo(2, "nSl")
          if string.match(called_from.short_src, "/queue.lua$") then
            return real_now() + now_offset
          else
            return real_now()
          end
        end,
        worker = {
          exiting = function()
            return false
          end
        }
      }
    })
  end)

  after_each(unmock)

  it("passes configuration to handler", function ()
    local handler_invoked
    local configuration_sent = { foo = "bar" }
    local configuration_received
    Queue.enqueue(
      queue_conf({ name = "handler-configuration" }),
      function (conf)
        handler_invoked = true
        configuration_received = conf
        return true
      end,
      configuration_sent,
      "ENTRY"
    )
    wait_until_queue_done("handler-configuration")
    helpers.wait_until(
      function ()
        if handler_invoked then
          assert.same(configuration_sent, configuration_received)
          return true
        end
      end,
      10)
  end)

  it("displays log_tag in log entries", function ()
    local handler_invoked
    local log_tag = uuid()
    Queue.enqueue(
      queue_conf({ name = "log-tag", log_tag = log_tag }),
      function ()
        handler_invoked = true
        return true
      end,
      nil,
      "ENTRY"
    )
    wait_until_queue_done("handler-configuration")
    helpers.wait_until(
      function ()
        if handler_invoked then
          return true
        end
      end,
      10)
    assert.match_re(log_messages, "" .. log_tag .. ".*done processing queue")
  end)

  it("configuration changes are observed for older entries", function ()
    local handler_invoked
    local first_configuration_sent = { foo = "bar" }
    local second_configuration_sent = { foo = "bar" }
    local configuration_received
    local number_of_entries_received
    local function enqueue(conf, entry)
      Queue.enqueue(
        queue_conf({
          name = "handler-configuration-change",
          max_batch_size = 10,
          max_coalescing_delay = 0.1
        }),
        function (c, entries)
          handler_invoked = true
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
    wait_until_queue_done("handler-configuration-change")
    helpers.wait_until(
      function ()
        if handler_invoked then
          assert.same(configuration_received, second_configuration_sent)
          assert.equals(2, number_of_entries_received)
          return true
        end
      end,
      10)
  end)

  it("does not batch messages when `max_batch_size` is 1", function()
    local process_count = 0
    local function enqueue(entry)
      Queue.enqueue(
        queue_conf({ name = "no-batch", max_batch_size = 1 }),
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
    wait_until_queue_done("no-batch")
    assert.equals(2, process_count)
  end)

  it("batches messages when `max_batch_size` is 2", function()
    local process_count = 0
    local first_entry, last_entry
    local function enqueue(entry)
      Queue.enqueue(
        queue_conf({
          name = "batch",
          max_batch_size = 2,
          max_coalescing_delay = 0.1,
        }),
        function(_, batch)
          first_entry = first_entry or batch[1]
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
    wait_until_queue_done("batch")
    assert.equals(3, process_count)
    assert.equals("One", first_entry)
    assert.equals("Five", last_entry)
  end)

  it("batches messages during shutdown", function()
    _G.ngx.worker.exiting = function()
      return true
    end
    local process_count = 0
    local first_entry, last_entry
    local function enqueue(entry)
      Queue.enqueue(
        queue_conf({
          name = "batch",
          max_batch_size = 2,
          max_coalescing_delay = 0.1,
        }),
        function(_, batch)
          first_entry = first_entry or batch[1]
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
    wait_until_queue_done("batch")
    assert.equals(3, process_count)
    assert.equals("One", first_entry)
    assert.equals("Five", last_entry)
  end)

  it("observes the `max_coalescing_delay` parameter", function()
    local process_count = 0
    local first_entry, last_entry
    local function enqueue(entry)
      Queue.enqueue(
        queue_conf({
          name = "batch",
          max_batch_size = 2,
          max_coalescing_delay = 3,
        }),
        function(_, batch)
          first_entry = first_entry or batch[1]
          last_entry = batch[#batch]
          process_count = process_count + 1
          return true
        end,
        nil,
        entry
      )
    end
    enqueue("One")
    ngx.sleep(1)
    enqueue("Two")
    wait_until_queue_done("batch")
    assert.equals(1, process_count)
    assert.equals("One", first_entry)
    assert.equals("Two", last_entry)
  end)

  it("retries sending messages", function()
    local process_count = 0
    local entry
    Queue.enqueue(
      queue_conf({
        name = "retry",
        max_batch_size = 1,
        max_coalescing_delay = 0.1,
      }),
      function(_, batch)
        entry = batch[1]
        process_count = process_count + 1
        return process_count == 2
      end,
      nil,
      "Hello"
    )
    wait_until_queue_done("retry")
    assert.equal(2, process_count)
    assert.equal("Hello", entry)
  end)

  it("gives up sending after retrying", function()
    local function enqueue(entry)
      Queue.enqueue(
        queue_conf({
          name = "retry-give-up",
          max_batch_size = 1,
          max_retry_time = 1,
          max_coalescing_delay = 0.1,
        }),
        function()
          return false, "FAIL FAIL FAIL"
        end,
        nil,
        entry
      )
    end

    enqueue("Hello")
    enqueue("another value")
    wait_until_queue_done("retry-give-up")
    assert.match_re(log_messages, 'WARN .* handler could not process entries: FAIL FAIL FAIL')
    assert.match_re(log_messages, 'ERR .*1 queue entries were lost')
  end)

  it("warns when queue reaches its capacity limit", function()
    local capacity = 100
    local function enqueue(entry)
      Queue.enqueue(
        queue_conf({
          name = "capacity-warning",
          max_batch_size = 1,
          max_entries = capacity,
          max_coalescing_delay = 0.1,
        }),
        function()
          return false
        end,
        nil,
        entry
      )
    end
    for _ = 1, math.floor(capacity * Queue._CAPACITY_WARNING_THRESHOLD) - 1 do
      enqueue("something")
    end
    assert.has.no.match_re(log_messages, "WARN .*queue at \\d*% capacity")
    enqueue("something")
    enqueue("something")
    assert.match_re(log_messages, "WARN .*queue at \\d*% capacity")
    log_messages = ""
    enqueue("something")
    assert.has.no.match_re(
      log_messages,
      "WARN .*queue at \\d*% capacity",
      "the capacity warning should not be logged more than once"
    )
  end)

  it("drops entries when queue reaches its capacity", function()
    local processed
    local function enqueue(entry)
      Queue.enqueue(
        queue_conf({
          name = "capacity-exceeded",
          max_batch_size = 2,
          max_entries = 2,
          max_coalescing_delay = 0.1,
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
    wait_until_queue_done("capacity-exceeded")
    assert.equal("Four", processed[1])
    assert.equal("Five", processed[2])
    assert.match_re(log_messages, "ERR .*queue full")
    enqueue("Six")
    wait_until_queue_done("capacity-exceeded")
    assert.equal("Six", processed[1])
    assert.match_re(log_messages, "INFO .*queue resumed processing")
  end)

  it("queue does not fail for max batch size = max entries", function()
    local fail_process = true
    local function enqueue(entry)
      Queue.enqueue(
        queue_conf({
          name = "capacity-exceeded",
          max_batch_size = 2,
          max_entries = 2,
          max_coalescing_delay = 0.1,
        }),
        function(_, batch)
          ngx.sleep(1)
          if fail_process then
            return false, "FAIL FAIL FAIL"
          end
          return true
        end,
        nil,
        entry
      )
    end
    -- enqueue 2 entries, enough for first batch
    for i = 1, 2 do
      enqueue("initial batch: " .. tostring(i))
    end
    -- wait for max_coalescing_delay such that the first batch is processed (and will be stuck in retry loop, as our handler always fails)
    ngx.sleep(0.1)
    -- fill in some more entries
    for i = 1, 2 do
      enqueue("fill up: " .. tostring(i))
    end
    fail_process = false
    wait_until_queue_done("capacity-exceeded")
  end)

  it("drops entries when it reaches its max_bytes", function()
    local processed
    local function enqueue(entry)
      Queue.enqueue(
        queue_conf({
          name = "string-capacity-exceeded",
          max_batch_size = 1,
          max_bytes = 6,
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
    wait_until_queue_done("string-capacity-exceeded")
    assert.equal("4444", processed[1])
    assert.match_re(log_messages, "ERR .*byte capacity exceeded, 3 queue entries were dropped")

    enqueue("55555")
    wait_until_queue_done("string-capacity-exceeded")
    assert.equal("55555", processed[1])

    enqueue("666666")
    wait_until_queue_done("string-capacity-exceeded")
    assert.equal("666666", processed[1])
  end)

  it("warns about improper max_bytes setting", function()
    local function enqueue(entry)
      Queue.enqueue(
        queue_conf({
          name = "string-capacity-warnings",
          max_batch_size = 1,
          max_bytes = 1,
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
      [[ERR .*string to be queued is longer \(2 bytes\) than the queue's max_bytes \(1 bytes\)]])
    log_messages = ""

    enqueue({ foo = "bar" })
    assert.match_re(log_messages,
      "ERR .*queuing non-string entry to a queue that has queue.max_bytes set, capacity monitoring will not be correct")
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
          max_batch_size = 10,
          max_coalescing_delay = 0.1,
        }),
        function(_, entries)
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

  it("works when time is moved forward while items are being queued", function()
    local number_of_entries = 1000
    local number_of_entries_processed = 0
    now_offset = 1
    for i = 1, number_of_entries do
      Queue.enqueue(
        queue_conf({
          name = "time-forwards-adjust",
          max_batch_size = 10,
          max_coalescing_delay = 10,
        }),
        function(_, entries)
          number_of_entries_processed = number_of_entries_processed + #entries
          return true
        end,
        nil,
        i
      )
      -- manipulate the current time forwards to simulate multiple time changes while entries are added to the queue
      now_offset = now_offset + now_offset
    end
    helpers.wait_until(
      function ()
        return number_of_entries_processed == number_of_entries
      end,
      10
    )
  end)

  it("works when time is moved backward while items are being queued", function()
    -- In this test, we move the time forward while we're sending out items.  The parameters are chosen so that
    -- time changes are likely to occur while enqueuing and while sending.
    local number_of_entries = 100
    local number_of_entries_processed = 0
    now_offset = -1
    for i = 1, number_of_entries do
      Queue.enqueue(
        queue_conf({
          name = "time-backwards-adjust",
          max_batch_size = 10,
          max_coalescing_delay = 10,
        }),
        function(_, entries)
          number_of_entries_processed = number_of_entries_processed + #entries
          ngx.sleep(0.2)
          return true
        end,
        nil,
        i
      )
      ngx.sleep(0.01)
      now_offset = now_offset + now_offset
    end
    helpers.wait_until(
      function ()
        return number_of_entries_processed == number_of_entries
      end,
      10
    )
  end)

  it("works when time is moved backward while items are on the queue and not yet processed", function()
    -- In this test, we manipulate the time backwards while we're sending out items.  The parameters are chosen so that
    -- time changes are likely to occur while enqueuing and while sending.
    local number_of_entries = 100
    local last
    local qconf = queue_conf({
      name = "time-backwards-blocked-adjust",
      max_batch_size = 10,
      max_coalescing_delay = 0.1,
    })
    local handler = function(_, entries)
      last = entries[#entries]
      ngx.sleep(0.2)
      return true
    end
    now_offset = -1
    for i = 1, number_of_entries do
      Queue.enqueue(qconf, handler, nil, i)
      ngx.sleep(0.01)
      now_offset = now_offset - 1000
    end
    helpers.wait_until(
      function()
        return not Queue._exists(qconf.name)
      end,
      10
    )
    Queue.enqueue(qconf, handler, nil, "last")
    helpers.wait_until(
      function()
        return last == "last"
      end,
      10
    )
  end)

  it("works when time is moved forward while items are on the queue and not yet processed", function()
    local number_of_entries = 100
    local last
    local qconf = queue_conf({
      name = "time-forwards-blocked-adjust",
      max_batch_size = 10,
      max_coalescing_delay = 0.1,
    })
    local handler = function(_, entries)
      last = entries[#entries]
      ngx.sleep(0.2)
      return true
    end
    now_offset = 1
    for i = 1, number_of_entries do
      Queue.enqueue(qconf, handler, nil, i)
      now_offset = now_offset + 1000
    end
    helpers.wait_until(
      function()
        return not Queue._exists(qconf.name)
      end,
      10
    )
    Queue.enqueue(qconf, handler, nil, "last")
    helpers.wait_until(
      function()
        return last == "last"
      end,
      10
    )
  end)

  it("converts common legacy queue parameters", function()
    local legacy_parameters = {
      retry_count = 123,
      queue_size = 234,
      flush_timeout = 345,
      queue = {
        name = "common-legacy-conversion-test",
      },
    }
    local converted_parameters = Queue.get_plugin_params("someplugin", legacy_parameters)
    assert.match_re(log_messages, 'the retry_count parameter no longer works, please update your configuration to use initial_retry_delay and max_retry_time instead')
    assert.equals(legacy_parameters.queue_size, converted_parameters.max_batch_size)
    assert.match_re(log_messages, 'the queue_size parameter is deprecated, please update your configuration to use queue.max_batch_size instead')
    assert.equals(legacy_parameters.flush_timeout, converted_parameters.max_coalescing_delay)
    assert.match_re(log_messages, 'the flush_timeout parameter is deprecated, please update your configuration to use queue.max_coalescing_delay instead')
  end)

  it("converts opentelemetry plugin legacy queue parameters", function()
    local legacy_parameters = {
      batch_span_count = 234,
      batch_flush_delay = 345,
      queue = {
        name = "opentelemetry-legacy-conversion-test",
      },
    }
    local converted_parameters = Queue.get_plugin_params("someplugin", legacy_parameters)
    assert.equals(legacy_parameters.batch_span_count, converted_parameters.max_batch_size)
    assert.match_re(log_messages, 'the batch_span_count parameter is deprecated, please update your configuration to use queue.max_batch_size instead')
    assert.equals(legacy_parameters.batch_flush_delay, converted_parameters.max_coalescing_delay)
    assert.match_re(log_messages, 'the batch_flush_delay parameter is deprecated, please update your configuration to use queue.max_coalescing_delay instead')
  end)

  it("logs deprecation messages only every so often", function()
    local legacy_parameters = {
      retry_count = 123,
      queue = {
        name = "legacy-warning-suppression",
      },
    }
    for _ = 1,10 do
      Queue.get_plugin_params("someplugin", legacy_parameters)
    end
    assert.equals(1, count_matching_log_messages('the retry_count parameter no longer works'))
    now_offset = 1000
    for _ = 1,10 do
      Queue.get_plugin_params("someplugin", legacy_parameters)
    end
    assert.equals(2, count_matching_log_messages('the retry_count parameter no longer works'))
  end)

  it("defaulted legacy parameters are ignored when converting", function()
    local legacy_parameters = {
      queue_size = 1,
      flush_timeout = 2,
      batch_span_count = 200,
      batch_flush_delay = 3,
      queue = {
        max_batch_size = 123,
        max_coalescing_delay = 234,
      }
    }
    local converted_parameters = Queue.get_plugin_params("someplugin", legacy_parameters)
    assert.equals(123, converted_parameters.max_batch_size)
    assert.equals(234, converted_parameters.max_coalescing_delay)
  end)

  it("continue processing after hard error in handler", function()
    local processed = {}
    local function enqueue(entry)
      Queue.enqueue(
        queue_conf({
          name = "continue-processing",
          max_batch_size = 1,
          max_entries = 5,
          max_coalescing_delay = 0.1,
          max_retry_time = 3,
        }),
        function(_, batch)
          if batch[1] == "Two" then
            error("hard error")
          end
          table.insert(processed, batch[1])
          return true
        end,
        nil,
        entry
      )
    end
    enqueue("One")
    enqueue("Two")
    enqueue("Three")
    wait_until_queue_done("continue-processing")
    assert.equal("One", processed[1])
    assert.equal("Three", processed[2])
    assert.match_re(log_messages, 'WARN \\[\\] queue continue-processing: handler could not process entries: .*: hard error')
    assert.match_re(log_messages, 'ERR \\[\\] queue continue-processing: could not send entries due to max_retry_time exceeded. \\d queue entries were lost')
  end)

  it("sanity check for function Queue.is_full() & Queue.can_enqueue()", function()
    local queue_conf = {
      name = "queue-full-checking-too-many-entries",
      max_batch_size = 99999, -- avoiding automatically flushing,
      max_entries = 2,
      max_bytes = nil, -- avoiding bytes limit
      max_coalescing_delay = 99999, -- avoiding automatically flushing,
      max_retry_time = 60,
      initial_retry_delay = 1,
      max_retry_delay = 60,
      concurrency_limit = 1,
    }

    local function enqueue(queue_conf, entry)
      Queue.enqueue(
        queue_conf,
        function()
          return true
        end,
        nil,
        entry
      )
    end

    -- should be true if the queue does not exist
    assert.is_true(Queue.can_enqueue(queue_conf))

    assert.is_false(Queue.is_full(queue_conf))
    assert.is_true(Queue.can_enqueue(queue_conf, "One"))
    enqueue(queue_conf, "One")
    assert.is_false(Queue.is_full(queue_conf))

    assert.is_true(Queue.can_enqueue(queue_conf, "Two"))
    enqueue(queue_conf, "Two")
    assert.is_true(Queue.is_full(queue_conf))

    assert.is_false(Queue.can_enqueue(queue_conf, "Three"))


    queue_conf = {
      name = "queue-full-checking-too-many-bytes",
      max_batch_size = 99999, -- avoiding automatically flushing,
      max_entries = 99999, -- big enough to avoid entries limit
      max_bytes = 2,
      max_coalescing_delay = 99999, -- avoiding automatically flushing,
      max_retry_time = 60,
      initial_retry_delay = 1,
      max_retry_delay = 60,
      concurrency_limit = 1,
    }

    -- should be true if the queue does not exist
    assert.is_true(Queue.can_enqueue(queue_conf))

    assert.is_false(Queue.is_full(queue_conf))
    assert.is_true(Queue.can_enqueue(queue_conf, "1"))
    enqueue(queue_conf, "1")
    assert.is_false(Queue.is_full(queue_conf))

    assert.is_true(Queue.can_enqueue(queue_conf, "2"))
    enqueue(queue_conf, "2")
    assert.is_true(Queue.is_full(queue_conf))

    assert.is_false(Queue.can_enqueue(queue_conf, "3"))

    queue_conf = {
      name = "queue-full-checking-too-large-entry",
      max_batch_size = 99999, -- avoiding automatically flushing,
      max_entries = 99999, -- big enough to avoid entries limit
      max_bytes = 3,
      max_coalescing_delay = 99999, -- avoiding automatically flushing,
      max_retry_time = 60,
      initial_retry_delay = 1,
      max_retry_delay = 60,
      concurrency_limit = 1,
    }

    -- should be true if the queue does not exist
    assert.is_true(Queue.can_enqueue(queue_conf))

    enqueue(queue_conf, "1")

    assert.is_false(Queue.is_full(queue_conf))
    assert.is_true(Queue.can_enqueue(queue_conf, "1"))
    assert.is_true(Queue.can_enqueue(queue_conf, "11"))
    assert.is_false(Queue.can_enqueue(queue_conf, "111"))
  end)
end)
