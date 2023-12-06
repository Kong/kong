-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson = require "cjson"

local fmt = string.format

-- preload utils module and patch it with a request mock
-- XXX does this affect any other test?
local utils = mock(require "kong.enterprise_edition.utils")
package.loaded["kong.enterprise_edition.utils"] = utils
package.loaded["kong.enterprise_edition.utils"].request = mock(function()
  return { body = "", headers = {}, status = 200 }
end)

local request = utils.request

local match = require("luassert.match")

local function is_request(state, arguments)
  local compare_no_order = require "pl.tablex".compare_no_order
  return function(value)
    return compare_no_order(arguments[1], value)
  end
end
assert:register("matcher", "is_request", is_request)

local function mock_cache()
  local store = {}
  local clock = 0

  return {
    mlcache = {
      lru = {
        set = function(self, key, value)
          store[key] = { value = value, opts = {} }
        end,
      },
    },
    get = function(self, key, opts, callback, ...)
      local args = { ... }
      local thing = store[key]
      local hit_lvl

      -- lol... invalidate
      if thing and thing.ttl and thing.ttl < clock then
        store[key] = nil
        thing = nil
      end

      if not thing then
        local value, opts, ttl = callback(unpack(args))
        thing = {
          value = value,
          opts = opts,
          ttl = ttl ~= nil and clock + ttl or nil,
        }
        store[key] = thing
        hit_lvl = 3
      else
        hit_lvl = 1
      end

      return thing.value, nil, hit_lvl

     end,
     _travel = function(time)
       clock = clock + time
     end,
     _store = store,
     _nuke = function()
       store = {}
     end,
  }
end

describe("mock_cache", function()
  local cache = mock_cache()

  before_each(function()
    cache._nuke()
  end)

  it("pretends to be mlcache", function()
    -- Miss
    local val, _, hit_lvl = cache:get("some_key", nil, function(some, arg)
      return { some, arg }
    end, "hello", "world")
    assert.same({ "hello", "world" }, val)
    assert.equal(3, hit_lvl)

    -- Hit
    val, _, hit_lvl = cache:get("some_key", nil, function(some, arg)
      return { some, arg }
    end, "hello", "world")
    assert.same({ "hello", "world" }, val)
    assert.equal(1, hit_lvl)

    -- Miss
    val, _, hit_lvl = cache:get("another_key", nil, function()
      return "hello!", nil, 20
    end)
    assert.same("hello!", val)
    assert.equal(3, hit_lvl)

    -- Hit
    val, _, hit_lvl = cache:get("another_key", nil, function()
      return "hello!", nil, 20
    end)
    assert.same("hello!", val)
    assert.equal(1, hit_lvl)

    -- Time travel 100 seconds
    cache._travel(100)

    -- Miss
    val, _, hit_lvl = cache:get("another_key", nil, function()
      return "hello!", nil, 20
    end)
    assert.same("hello!", val)
    assert.equal(3, hit_lvl)

    -- Time travel 10 seconds
    cache._travel(10)

    -- Hit
    val, _, hit_lvl = cache:get("another_key", nil, function()
      return "hello!", nil, 20
    end)
    assert.same("hello!", val)
    assert.equal(1, hit_lvl)

    -- Time travel 15 seconds
    cache._travel(15)

    -- Miss
    val, _, hit_lvl = cache:get("another_key", nil, function()
      return "hello!", nil, 20
    end)
    assert.same("hello!", val)
    assert.equal(3, hit_lvl)
  end)
end)

describe("event-hooks", function()

  local event_hooks = require "kong.enterprise_edition.event_hooks"

  -- reset any mocks, stubs, whatever was messed up on _G.kong and event-hooks
  before_each(function()
    _G.kong = {
      configuration = {
        event_hooks_enabled = true,
      },
      worker_events = {},
      cache = mock_cache(),
      log = mock(setmetatable({}, { __index = function() return function() end end })),
    }

    for k, v in pairs(event_hooks.events) do
      event_hooks.events[k] = nil
    end

    for k, v in pairs(event_hooks.references) do
      event_hooks.references[k] = nil
    end

    mock.revert(event_hooks)
    mock.revert(kong)
  end)

  describe("disabled", function()
    before_each(function()
      _G.kong = {
        configuration = {
          event_hooks_enabled = false,
        }
      }
    end)

    it("does nothing", function()
      assert.is_nil(event_hooks.publish())
      assert.is_nil(event_hooks.register())
      assert.is_nil(event_hooks.unregister())
      assert.is_nil(event_hooks.emit())
    end)
  end)

  describe("publish / #list", function()
    describe("any code can publish a source/event", function()
      it("with a source and an event", function()
        assert(event_hooks.publish("some_source", "some_event"))
      end)

      it("with source, event and opts", function()
        assert(event_hooks.publish("some_source", "some_event", {
          description = "Some event that does something",
          fields = { "foo", "bar" },
          unique = { "foo" },
        }))
      end)
    end)

    it("publish stores them, and list lists them", function()
      assert(event_hooks.publish("some_source", "some_event", {
          description = "Some event that does something",
          fields = { "foo", "bar" },
          unique = { "foo" },
      }))
      assert(event_hooks.publish("another_source", "another_event"))
      local expected = {
        some_source = {
          some_event = {
            description = "Some event that does something",
            fields = { "foo", "bar" },
            unique = { "foo" },
          }
        },
        another_source = {
          another_event = {}
        },
      }
      assert.same(expected, event_hooks.list())
    end)
  end)

  describe("register", function()
    local mock_function = function() end
    local some_entity

    before_each(function()
      stub(kong.worker_events, "register")
      stub(event_hooks, "callback").returns(mock_function)
      some_entity = {
        id = "a4fbd24e-6a52-4937-bd78-2536713072d2",
        source = "some_source",
        event = "some_event",
      }
    end)

    describe("receives an entity and registers a worker_event", function()
      it("with a callback, a source and an event", function()
        event_hooks.register(some_entity)
        assert.stub(kong.worker_events.register)
              .was.called_with(mock_function, "event-hooks:some_source", "some_event")
      end)
      it("an entity can have a nil event", function()
        some_entity.event = nil
        event_hooks.register(some_entity)
        assert.stub(kong.worker_events.register)
              .was.called_with(mock_function, "event-hooks:some_source", nil)
      end)
      it("an entity can have a ngx.null event that is nil too", function()
        some_entity.event = ngx.null
        event_hooks.register(some_entity)
        assert.stub(kong.worker_events.register)
              .was.called_with(mock_function, "event-hooks:some_source", nil)
      end)
    end)
  end)

  describe("unregister", function()
    local mock_function = function() end
    local some_entity

    before_each(function()
      stub(event_hooks, "callback").returns(mock_function)
      stub(kong.worker_events, "register")
      stub(kong.worker_events, "unregister")

      some_entity = {
        id = "a4fbd24e-6a52-4937-bd78-2536713072d2",
        source = "some_source",
        event = "some_event",
      }
    end)

    describe("receives an entity and unregisters an existing worker_event by id", function()
      it("with the original callback, a source and an event", function()
        event_hooks.register(some_entity)
        stub(event_hooks, "callback").returns(function() end)
        event_hooks.unregister(some_entity)
        assert.stub(kong.worker_events.unregister)
              .was.called_with(mock_function, "event-hooks:some_source", "some_event")
      end)
      it("an entity can have a nil event", function()
        some_entity.event = nil
        event_hooks.register(some_entity)
        stub(event_hooks, "callback").returns(function() end)
        event_hooks.unregister(some_entity)
        assert.stub(kong.worker_events.unregister)
              .was.called_with(mock_function, "event-hooks:some_source", nil)
      end)
      it("an entity can have a ngx.null event that is nil too", function()
        some_entity.event = ngx.null
        event_hooks.register(some_entity)
        stub(event_hooks, "callback").returns(function() end)
        event_hooks.unregister(some_entity)
        assert.stub(kong.worker_events.unregister)
              .was.called_with(mock_function, "event-hooks:some_source", nil)
      end)
    end)
  end)

  describe("emit", function()
    before_each(function()
      stub(kong.worker_events, "post")
    end)

    describe("receives a source, an event and some data", function()
      it("calls worker_events post", function()
        event_hooks.emit("some_source", "some_event", { some = "data" })
        local unique = "some_source:some_event:bc31a334fcc4ed689f4ea9ab824f23b3"
        local source = "event-hooks:some_source"
        local event = "some_event"
        local data = { some = "data" }
        assert.stub(kong.worker_events.post)
              .was.called_with(source, event, data, unique)
      end)
    end)
  end)

  describe("digest", function()
    describe("generates the digest of a data message", function()
      it("defaults to the whole data when an event has not been published", function()
        local data = { some = "data", with_more = "data" }
        assert.equal("80dfae20a5ce00b394c00a4c42658c67",
                     event_hooks.digest(data))
      end)

      it("two data messages have the same digest if their relevant fields are the same", function()
        local data = { some = "data", with_more = "data", and_more = "data" }
        local more_data = { some = "data", with_more = "data", and_more = "snowflake" }
        local fields = { "some", "with_more" }

        assert.equal("80dfae20a5ce00b394c00a4c42658c67",
                     event_hooks.digest(data, { fields = fields }))
        assert.equal(event_hooks.digest(more_data, { fields = fields }),
                     event_hooks.digest(data, { fields = fields }))
      end)

      it("changes digest when a relevant field changes", function()
        local data = { some = "data", with_more = "data", and_more = "data" }
        local more_data = { some = "data", with_more = "snowflake", and_more = "snowflake" }
        local fields = { "some", "with_more" }

        assert.not_equal(event_hooks.digest(data, { fields = fields }),
                         event_hooks.digest(more_data, { fields = fields }))
      end)

      it("does safely break when data is not serializable", function()
        local data = { non_serializable = function() end }
        local digest, err = event_hooks.digest(data)
        assert.is_nil(digest)
        assert.not_nil(err)
      end)
    end)
  end)

  describe("handlers and callbacks", function()
    describe("given a worker_event, an event_hooks handler and an event_hooks entity", function()
      local handler, handler_cb, entity, worker_event

      before_each(function()
        stub(event_hooks, "enqueue")

        worker_event = {
          data = { some = "data" },
          event = "some_event",
          source = "some_source",
          pid = 1234,
        }

        handler = "some_handler"
        handler_cb = function(data, event, source, pid) end
        stub(event_hooks.handlers, handler).returns({ callback = handler_cb })

        entity = {
          id = "a4fbd24e-6a52-4937-bd78-2536713072d2",
          source = worker_event.source,
          event = worker_event.event,
          handler = handler,
          config = {
            some = "configuration",
          }
        }

      end)

      it("a blob with the handler function as a callback is enqueued", function()
        event_hooks.callback(entity)(worker_event.data,
                                 worker_event.event,
                                 worker_event.source,
                                 worker_event.pid)
        local blob = {
          callback = handler_cb,
          args = { worker_event.data, worker_event.event, worker_event.source, worker_event.pid },
        }

        assert.stub(event_hooks.enqueue).was.called_with(blob)
      end)

      describe("on_change", function()
        it("when false, enqueues event_hooks job as many times as called", function()
          entity.on_change = false
          event_hooks.callback(entity)(worker_event.data,
                                   worker_event.event,
                                   worker_event.source,
                                   worker_event.pid)
          assert.stub(event_hooks.enqueue).was.called(1)

          event_hooks.callback(entity)(worker_event.data,
                                   worker_event.event,
                                   worker_event.source,
                                   worker_event.pid)
          assert.stub(event_hooks.enqueue).was.called(2)
        end)
        it("when true, enqueues event_hooks job only if data signature has changed", function()
          entity.on_change = true

          worker_event.data = { some = "data" }
          event_hooks.callback(entity)(worker_event.data,
                                   worker_event.event,
                                   worker_event.source,
                                   worker_event.pid)
          assert.stub(event_hooks.enqueue).was.called(1)

          worker_event.data = { some = "data" }
          event_hooks.callback(entity)(worker_event.data,
                                   worker_event.event,
                                   worker_event.source,
                                   worker_event.pid)
          assert.stub(event_hooks.enqueue).was.called(1)

          worker_event.data = { different = "data" }
          event_hooks.callback(entity)(worker_event.data,
                                   worker_event.event,
                                   worker_event.source,
                                   worker_event.pid)
          assert.stub(event_hooks.enqueue).was.called(2)

          worker_event.data = { different = "data" }
          event_hooks.callback(entity)(worker_event.data,
                                   worker_event.event,
                                   worker_event.source,
                                   worker_event.pid)
          assert.stub(event_hooks.enqueue).was.called(2)

          worker_event.data = { some = "data" }
          event_hooks.callback(entity)(worker_event.data,
                                   worker_event.event,
                                   worker_event.source,
                                   worker_event.pid)
          assert.stub(event_hooks.enqueue).was.called(3)
        end)
        it("does ignore on_change if event data is not serializable", function()
          entity.on_change = true
          worker_event.data = { some = function() end }
          event_hooks.callback(entity)(worker_event.data,
                                   worker_event.event,
                                   worker_event.source,
                                   worker_event.pid)
          assert.stub(event_hooks.enqueue).was.called(1)

          event_hooks.callback(entity)(worker_event.data,
                                   worker_event.event,
                                   worker_event.source,
                                   worker_event.pid)
          assert.stub(event_hooks.enqueue).was.called(2)
        end)
      end)

      describe("snooze", function()
        it("when set, disables a event_hooks event for 'snooze' seconds", function()
          entity.snooze = 60

          event_hooks.callback(entity)(worker_event.data,
                                   worker_event.event,
                                   worker_event.source,
                                   worker_event.pid)
          assert.stub(event_hooks.enqueue).was.called(1)

          event_hooks.callback(entity)(worker_event.data,
                                   worker_event.event,
                                   worker_event.source,
                                   worker_event.pid)
          assert.stub(event_hooks.enqueue).was.called(1)

          -- 50 seconds pass
          kong.cache._travel(50)
          event_hooks.callback(entity)(worker_event.data,
                                   worker_event.event,
                                   worker_event.source,
                                   worker_event.pid)
          assert.stub(event_hooks.enqueue).was.called(1)

          -- 20 more seconds pass (70 seconds)
          kong.cache._travel(20)
          event_hooks.callback(entity)(worker_event.data,
                                   worker_event.event,
                                   worker_event.source,
                                   worker_event.pid)
          assert.stub(event_hooks.enqueue).was.called(2)

          -- now it should be snoozed for 60 more seconds (130 seconds)
          -- 30 seconds pass
          kong.cache._travel(30)
          event_hooks.callback(entity)(worker_event.data,
                                   worker_event.event,
                                   worker_event.source,
                                   worker_event.pid)
          assert.stub(event_hooks.enqueue).was.called(2)

          -- 31 seconds pass
          kong.cache._travel(31)
          event_hooks.callback(entity)(worker_event.data,
                                   worker_event.event,
                                   worker_event.source,
                                   worker_event.pid)
          assert.stub(event_hooks.enqueue).was.called(3)
        end)

        it("does ignore snooze if event data is not serializable", function()
          entity.snooze = 60
          worker_event.data = { some = function() end }
          event_hooks.callback(entity)(worker_event.data,
                                   worker_event.event,
                                   worker_event.source,
                                   worker_event.pid)
          assert.stub(event_hooks.enqueue).was.called(1)

          event_hooks.callback(entity)(worker_event.data,
                                   worker_event.event,
                                   worker_event.source,
                                   worker_event.pid)
          assert.stub(event_hooks.enqueue).was.called(2)
        end)
      end)

      describe("on_change + snooze", function()
        it("only events with different signatures get called during snooze time", function()
          entity.on_change = true
          entity.snooze = 60

          local different_data = { different = "data" }

          -- first event
          event_hooks.callback(entity)(worker_event.data,
                                   worker_event.event,
                                   worker_event.source,
                                   worker_event.pid)
          assert.stub(event_hooks.enqueue).was.called(1)

          -- 10 seconds
          kong.cache._travel(10)

          -- same as first
          event_hooks.callback(entity)(worker_event.data,
                                   worker_event.event,
                                   worker_event.source,
                                   worker_event.pid)
          assert.stub(event_hooks.enqueue).was.called(1)

          -- different data
          event_hooks.callback(entity)(different_data,
                                   worker_event.event,
                                   worker_event.source,
                                   worker_event.pid)
          assert.stub(event_hooks.enqueue).was.called(2)

          -- 20 seconds
          kong.cache._travel(10)

          -- different data
          event_hooks.callback(entity)(different_data,
                                   worker_event.event,
                                   worker_event.source,
                                   worker_event.pid)
          assert.stub(event_hooks.enqueue).was.called(2)

          -- 61 seconds
          kong.cache._travel(41)

          -- first event
          event_hooks.callback(entity)(worker_event.data,
                                   worker_event.event,
                                   worker_event.source,
                                   worker_event.pid)
          assert.stub(event_hooks.enqueue).was.called(3)

          -- different data
          event_hooks.callback(entity)(worker_event.data,
                                   worker_event.event,
                                   worker_event.source,
                                   worker_event.pid)
          assert.stub(event_hooks.enqueue).was.called(3)

          -- 71 seconds
          kong.cache._travel(71)

          event_hooks.callback(entity)(worker_event.data,
                                   worker_event.event,
                                   worker_event.source,
                                   worker_event.pid)
          assert.stub(event_hooks.enqueue).was.called(4)
        end)
      end)
    end)

    -- process_callback is the function that executes callbacks on the
    -- batch queue. It must not kill the worker on unhandled errors
    describe("#process_callback", function()
      it("does gracefully return false on unhandled errors", function()
        local blob = {
          callback = function(data, event, source, pid)
            error("something bad")
          end,
          args = { { some = "data" }, "some_event", "some_source", 1234 },
        }

        local ok, err = event_hooks.process_callback(nil, { blob })
        assert.is_nil(ok)
        assert.matches("something bad", err)
      end)

      it("returns non-nil on correct execution", function()
        local blob = {
          callback = function(data, event, source, pid)
            return "hello world"
          end,
          args = { { some = "data" }, "some_event", "some_source", 1234 },
        }
        local res, err = event_hooks.process_callback(nil, { blob })
        assert.equal("hello world", res)
        assert.is_nil(err)
      end)

      it("sends data, event, source and pid to a callback from a blob", function()
        local data = { some = "data" }
        local event = "some_event"
        local source = "some_source"
        local pid = 1234
        local blob = {
          callback = function(data, event, source, pid)
            return { data, event, source, pid }
          end,
          args = { data, event, source, pid },
        }
        local res, _ = event_hooks.process_callback(nil, { blob })
        assert.same({ data, event, source, pid }, res)
      end)
    end)

    for _, untrusted in ipairs({ 'on', 'sandbox' }) do
      describe(fmt("[#lambda] untrusted_lua = '%s' ", untrusted), function()
        local entity
        local handler = event_hooks.handlers.lambda

        local sandbox = require "kong.tools.sandbox"

        before_each(function()
          _G.kong.configuration.untrusted_lua = untrusted
          sandbox.configuration:reload()
        end)

        lazy_teardown(function()
          _G.kong.configuration.untrusted_lua = nil
          sandbox.configuration:reload()
        end)

        before_each(function()
          entity = {
            id = "a4fbd24e-6a52-4937-bd78-2536713072d2",
            source = "some_source",
            event = "some_event",
            handler = "lambda",
            config = {},
          }
          -- reset mock counters
          request:clear()
        end)

        -- subschema does not handle defaults and required nested fields very
        -- well, so we have to assume an empty config might happen.
        it("does not break on empty config", function()
          local cb = handler(entity, entity.config).callback
          assert(cb({ some = "data"}, "some_event", "some_source", 1234))
        end)

        it("reduces over a set of configured functions", function()
          entity.config.functions = {
            [[
              return function(data, event, source, pid)
                return "HELLO"
              end
            ]],
            [[
              return function(data, event, source, pid)
                return data .. " WORLD"
              end
            ]],
          }
          local cb = handler(entity, entity.config).callback
          local res = cb({ some = "data"}, "some_event", "some_source", 1234)
          assert.equal("HELLO WORLD", res)
        end)

        it("returns false and error when a manual error happens", function()
          entity.config.functions = {
            [[
              return function(data, event, source, pid)
                return nil, "some bad error"
              end
            ]],
            [[
              return function(data, event, source, pid)
                return data .. " WORLD"
              end
            ]],
          }
          local cb = handler(entity, entity.config).callback
          local ok, err = cb({ some = "data"}, "some_event", "some_source", 1234)
          assert(not ok)
          assert.equal("some bad error", err)
        end)

        it("syntax errors return false and an error", function()
          entity.config.functions = {
            [[
              retarn finction(data, event, source, pid)
                return true
              end
            ]],
            [[
              return function(data, event, source, pid)
                return data .. " WORLD"
              end
            ]],
          }
          local cb = handler(entity, entity.config).callback
          local ok, err = cb({ some = "data"}, "some_event", "some_source", 1234)
          assert(not ok)
          assert.match("'=' expected near 'finction'", err)
        end)

      end)
    end

    describe("[webhook]", function()
      local entity
      local handler = event_hooks.handlers.webhook

      before_each(function()
        entity = {
          id = "a4fbd24e-6a52-4937-bd78-2536713072d2",
          source = "some_source",
          event = "some_event",
          handler = "webhook",
          config = {},
        }
        -- reset mock counters
        request:clear()
      end)

      it("makes a POST request with whole event as JSON data payload", function()
        entity.config = {
          url = "http://foobar.test",
        }
        local cb = handler(entity, entity.config).callback
        cb({ some = "data"}, "some_event", "some_source", 1234)

        local expected_body = '{"event":"some_event","some":"data","source":"some_source"}'

        local expected_headers = {
          ["content-type"] = "application/json",
        }

        assert.stub(request).was.called_with(entity.config.url, match.is_request({
          method = "POST",
          body = expected_body,
          headers = expected_headers,
        }))
      end)

      describe("secret", function()
        -- request responsibility to use this function to add a header
        it("sends a signing function to request", function()
          entity.config = {
            url = "http://foobar.test",
            secret = "hunter2",
          }
          local cb = handler(entity, entity.config).callback
          cb({ some = "data"}, "some_event", "some_source", 1234)
          local blob = request.calls[1].refs[2]
          assert.is_function(blob.sign_with)
          local alg, hmac = blob.sign_with("foobar")
          assert.equal("sha1", alg)
          assert.equal("47632029fcc7936dc59ff90b5bb736a44c74ab62", hmac)
        end)
      end)

      it("ssl verification can be disabled with ssl_verify", function()
        entity.config = {
          url = "https://not-really-secure.test",
          ssl_verify = false,
        }
        local cb = handler(entity, entity.config).callback
        cb({ some = "data"}, "some_event", "some_source", 1234)

        local expected_body = '{"event":"some_event","some":"data","source":"some_source"}'

        local expected_headers = {
          ["content-type"] = "application/json",
        }

        assert.stub(request).was.called_with(entity.config.url, match.is_request({
          method = "POST",
          body = expected_body,
          headers = expected_headers,
          ssl_verify = false,
        }))

      end)

      describe("ping", function()
        it("sends the event_hook entity to the url", function()
          entity.config = {
            url = "http://foobar.test",
            headers = { ["some-header"] = "some value" },
          }

          local ping = handler(entity, entity.config).ping
          assert(ping())

          local expected_body = cjson.encode({
            event_hooks = entity,
            event = "ping",
            source = "kong:event_hooks",
          })
          local expected_headers = {
            ["content-type"] = "application/json",
            ["some-header"] = "some value",
          }
          assert.stub(request).was.called_with(entity.config.url, match.is_request({
            method = "POST",
            headers = expected_headers,
            body = expected_body,
          }))
        end)

        it("has an operation argument", function()
          entity.config = {
            url = "http://foobar.test",
            headers = { ["some-header"] = "some value" },
          }

          local ping = handler(entity, entity.config).ping
          assert(ping("create"))

          local expected_body = cjson.encode({
            operation = "create",
            event_hooks = entity,
            event = "ping",
            source = "kong:event_hooks",
          })
          local expected_headers = {
            ["content-type"] = "application/json",
            ["some-header"] = "some value",
          }
          assert.stub(request).was.called_with(entity.config.url, match.is_request({
            method = "POST",
            headers = expected_headers,
            body = expected_body,
          }))
        end)
      end)

      describe("headers", function()
        it("sends headers", function()
          entity.config = {
            url = "http://foobar.test",
            headers = {
              ["X-Give-Me"] = "some tests",
            },
          }
          local cb = handler(entity, entity.config).callback
          cb({ some = "data"}, "some_event", "some_source", 1234)


          local expected_body = '{"event":"some_event","some":"data","source":"some_source"}'

          local expected_headers = {
            ["content-type"] = "application/json",
            ["X-Give-Me"] = "some tests",
          }
          assert.stub(request).was.called_with(entity.config.url, match.is_request({
            method = "POST",
            headers = expected_headers,
            body = expected_body,
          }))
        end)
      end)
    end)

    describe("[webhook-custom]", function()
      describe("makes a request", function()
        local entity
        local handler = event_hooks.handlers["webhook-custom"]

        before_each(function()
          entity = {
            id = "a4fbd24e-6a52-4937-bd78-2536713072d2",
            source = "some_source",
            event = "some_event",
            handler = "webhook-custom",
            config = {},
          }
          -- reset mock counters
          request:clear()
        end)

        it("to an url with a method", function()
          entity.config = {
            url = "http://foobar.test",
            method = "GET",
          }
          local cb = handler(entity, entity.config).callback
          cb({ some = "data"}, "some_event", "some_source", 1234)
          assert.stub(request).was.called_with(entity.config.url, {
            method = entity.config.method,
          })

          entity.config = {
            url = "http://foobar.test",
            method = "POST",
          }
          local cb = handler(entity, entity.config).callback
          cb({ some = "data"}, "some_event", "some_source", 1234)
          assert.stub(request).was.called_with(entity.config.url, {
            method = entity.config.method,
          })
        end)

        -- request responsability to do something with it
        describe("payload and payload_format", function()
          it("sends payload as a table", function()
            entity.config = {
              url = "http://foobar.test",
              method = "POST",
              payload = {
                some = "params",
                to = "convert",
                as_a = "body",
                -- but it's not our problem
              }
            }
            local cb = handler(entity, entity.config).callback
            cb({ some = "data"}, "some_event", "some_source", 1234)
            assert.stub(request).was.called_with(entity.config.url, {
              method = entity.config.method,
              data = entity.config.payload,
            })
          end)

          it("payload gets formatted", function()
            entity.config = {
              url = "http://foobar.test",
              method = "POST",
              payload_format = true,
              payload = {
                this_one = "is formatted with {{ some }}",
                -- but it's not our problem
              }
            }
            local cb = handler(entity, entity.config).callback
            cb({ some = "data"}, "some_event", "some_source", 1234)
            assert.stub(request).was.called_with(entity.config.url, {
              method = entity.config.method,
              data = {
                this_one = "is formatted with data",
              },
            })
          end)
        end)

        describe("body and body_format", function()
          it("sends arbitrary body", function()
            entity.config = {
              url = "http://foobar.test",
              method = "POST",
              body = [[
               { "some": "arbitrary body" }
              ]],
            }
            local cb = handler(entity, entity.config).callback
            cb({ some = "data"}, "some_event", "some_source", 1234)
            assert.stub(request).was.called_with(entity.config.url, {
              method = entity.config.method,
              body = entity.config.body,
            })
          end)

          it("body gets formatted", function()
            entity.config = {
              url = "http://foobar.test",
              method = "POST",
              body_format = true,
              body = [[
                { "some {{ some }}": "arbitrary body {{ some }}" }
              ]]
            }
            local cb = handler(entity, entity.config).callback
            cb({ some = "data"}, "some_event", "some_source", 1234)
            assert.stub(request).was.called_with(entity.config.url, {
              method = entity.config.method,
              body = [[
                { "some data": "arbitrary body data" }
              ]],
            })
          end)
        end)

        describe("secret", function()
          -- request responsability to use this function to add a header
          it("sends a signing function to request", function()
            entity.config = {
              url = "http://foobar.test",
              method = "POST",
              secret = "hunter2",
            }
            local cb = handler(entity, entity.config).callback
            cb({ some = "data"}, "some_event", "some_source", 1234)
            local blob = request.calls[1].refs[2]
            assert.is_function(blob.sign_with)
            local alg, hmac = blob.sign_with("foobar")
            assert.equal("sha1", alg)
            assert.equal("47632029fcc7936dc59ff90b5bb736a44c74ab62", hmac)
          end)
        end)

        describe("headers and headers_format", function()
          it("sends headers", function()
            entity.config = {
              url = "http://foobar.test",
              method = "GET",
              headers = {
                ["X-Give-Me"] = "some tests",
              },
            }
            local cb = handler(entity, entity.config).callback
            cb({ some = "data"}, "some_event", "some_source", 1234)
            assert.stub(request).was.called_with(entity.config.url, {
              method = entity.config.method,
              headers = entity.config.headers,
            })
          end)

          it("headers can be formatted with data", function()
            entity.config = {
              url = "http://foobar.test",
              method = "GET",
              headers = {
                ["X-Give-Me"] = "some tests {{ some }}",
              },
              headers_format = true,
            }
            local cb = handler(entity, entity.config).callback
            cb({ some = "data"}, "some_event", "some_source", 1234)
            assert.stub(request).was.called_with(entity.config.url, {
              method = entity.config.method,
              headers = {
                ["X-Give-Me"] = "some tests data",
              },
            })
          end)
        end)

        it("ssl verification can be disabled with ssl_verify", function()
          entity.config = {
            url = "https://not-really-secure.test",
            ssl_verify = false,
          }
          local cb = handler(entity, entity.config).callback
          cb({ some = "data"}, "some_event", "some_source", 1234)

          assert.stub(request).was.called_with(entity.config.url, {
            ssl_verify = false,
          })

        end)
      end)
    end)

    -- worth testing log handler?
    describe("[log]", function()
      it("does not break", function()
        local entity = {
          id = "a4fbd24e-6a52-4937-bd78-2536713072d2",
          source = "some_source",
          event = "some_event",
          handler = "log",
          config = {},
        }
        local handler = event_hooks.handlers.log
        local cb = handler(entity, entity.config).callback
        assert(cb({ some = "data"}, "some_event", "some_source", 1234))
      end)
    end)
  end)

  describe("ping", function()
    local handler, ping_spy, entity, worker_event
    local op = "create"

    before_each(function()
      worker_event = {
        data = { some = "data" },
        event = "some_event",
        source = "some_source",
        pid = 1234,
      }

      handler = "some_handler"
      ping_spy = spy.new(function(operation) return true end)
      stub(event_hooks.handlers, handler).returns({
        callback = function() end,
        ping = ping_spy,
      })

      entity = {
        id = "a4fbd24e-6a52-4937-bd78-2536713072d2",
        source = worker_event.source,
        event = worker_event.event,
        handler = handler,
        config = {
          some = "configuration",
        }
      }
    end)

    it("returns a handler's ping function if it's defined", function()
      assert(event_hooks.ping(entity, op))
      assert.spy(ping_spy).was.called_with(op)
    end)

    it("returns nil and an error if it's not defined", function()
      stub(event_hooks.handlers, handler).returns({
        callback = function() end,
      })
      local _, err = event_hooks.ping(entity, op)
      assert.equal("handler 'some_handler' does not support 'ping'", err)
    end)
  end)

end)
