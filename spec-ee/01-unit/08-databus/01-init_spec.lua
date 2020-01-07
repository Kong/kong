-- preload utils module and patch it with a request mock
-- XXX does this affect any other test?
local utils = mock(require "kong.enterprise_edition.utils")
package.loaded["kong.enterprise_edition.utils"] = utils
package.loaded["kong.enterprise_edition.utils"].request = mock(function() end)

local request = utils.request

local function mock_cache()
  local store = {}
  local clock = 0

  return {
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

describe("databus", function()

  local databus = require "kong.enterprise_edition.databus"

  -- reset any mocks, stubs, whatever was messed up on _G.kong and databus
  before_each(function()
    _G.kong = {
      configuration = {
        databus_enabled = true,
      },
      worker_events = {},
      cache = mock_cache(),
      log = mock(setmetatable({}, { __index = function() return function() end end })),
    }

    for k, v in pairs(databus.events) do
      databus.events[k] = nil
    end

    for k, v in pairs(databus.references) do
      databus.references[k] = nil
    end

    mock.revert(databus)
    mock.revert(kong)
  end)

  describe("disabled", function()
    before_each(function()
      _G.kong = {
        configuration = {
          databus_enabled = false,
        }
      }
    end)

    it("does nothing", function()
      assert.is_nil(databus.publish())
      assert.is_nil(databus.register())
      assert.is_nil(databus.unregister())
      assert.is_nil(databus.emit())
    end)
  end)

  describe("publish / #list", function()
    describe("any code can publish a source/event", function()
      it("with a source and an event", function()
        assert(databus.publish("some_source", "some_event"))
      end)

      it("with source, event and opts", function()
        assert(databus.publish("some_source", "some_event", {
          description = "Some event that does something",
          fields = { "foo", "bar" },
          unique = { "foo" },
        }))
      end)
    end)

    it("publish stores them, and list lists them", function()
      assert(databus.publish("some_source", "some_event", {
          description = "Some event that does something",
          fields = { "foo", "bar" },
          unique = { "foo" },
      }))
      assert(databus.publish("another_source", "another_event"))
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
      assert.same(expected, databus.list())
    end)
  end)

  describe("register", function()
    local mock_function = function() end
    local some_entity

    before_each(function()
      stub(kong.worker_events, "register")
      stub(databus, "callback").returns(mock_function)
      some_entity = {
        id = "a4fbd24e-6a52-4937-bd78-2536713072d2",
        source = "some_source",
        event = "some_event",
      }
    end)

    describe("receives an entity and registers a worker_event", function()
      it("with a callback, a source and an event", function()
        databus.register(some_entity)
        assert.stub(kong.worker_events.register)
              .was.called_with(mock_function, "some_source", "some_event")
      end)
      it("an entity can have a nil event", function()
        some_entity.event = nil
        databus.register(some_entity)
        assert.stub(kong.worker_events.register)
              .was.called_with(mock_function, "some_source", nil)
      end)
      it("an entity can have a ngx.null event that is nil too", function()
        some_entity.event = ngx.null
        databus.register(some_entity)
        assert.stub(kong.worker_events.register)
              .was.called_with(mock_function, "some_source", nil)
      end)
    end)
  end)

  describe("unregister", function()
    local mock_function = function() end
    local some_entity

    before_each(function()
      stub(databus, "callback").returns(mock_function)
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
        databus.register(some_entity)
        stub(databus, "callback").returns(function() end)
        databus.unregister(some_entity)
        assert.stub(kong.worker_events.unregister)
              .was.called_with(mock_function, "some_source", "some_event")
      end)
      it("an entity can have a nil event", function()
        some_entity.event = nil
        databus.register(some_entity)
        stub(databus, "callback").returns(function() end)
        databus.unregister(some_entity)
        assert.stub(kong.worker_events.unregister)
              .was.called_with(mock_function, "some_source", nil)
      end)
      it("an entity can have a ngx.null event that is nil too", function()
        some_entity.event = ngx.null
        databus.register(some_entity)
        stub(databus, "callback").returns(function() end)
        databus.unregister(some_entity)
        assert.stub(kong.worker_events.unregister)
              .was.called_with(mock_function, "some_source", nil)
      end)
    end)
  end)

  describe("emit", function()
    before_each(function()
      stub(kong.worker_events, "post_local")
    end)

    describe("receives a source, an event and some data", function()
      it("calls worker_events post_local with the source prefixed as dbus:", function()
        databus.emit("some_source", "some_event", { some = "data" })
        assert.stub(kong.worker_events.post_local)
              .was.called_with("some_source", "some_event", { some = "data" })
      end)
    end)
  end)

  describe("digest", function()
    describe("generates the digest of a data message", function()
      it("defaults to the whole data when an event has not been published", function()
        local data = { some = "data", with_more = "data" }
        assert.equal("fcd3b17e549f0a83f5bd14aa85d2f2cb",
                     databus.digest(data))
      end)

      it("two data messages have the same digest if their relevant fields are the same", function()
        local data = { some = "data", with_more = "data", and_more = "data" }
        local more_data = { some = "data", with_more = "data", and_more = "snowflake" }
        local fields = { "some", "with_more" }

        assert.equal("fcd3b17e549f0a83f5bd14aa85d2f2cb",
                     databus.digest(data, { fields = fields }))
        assert.equal(databus.digest(more_data, { fields = fields }),
                     databus.digest(data, { fields = fields }))
      end)

      it("changes digest when a relevant field changes", function()
        local data = { some = "data", with_more = "data", and_more = "data" }
        local more_data = { some = "data", with_more = "snowflake", and_more = "snowflake" }
        local fields = { "somne", "with_more" }

        assert.not_equal(databus.digest(data, { fields = fields }),
                         databus.digest(more_data, { fields = fields }))
      end)
    end)
  end)

  describe("handlers and callbacks", function()
    describe("given a worker_event, a dbus handler and a dbus entity", function()
      local handler, handler_cb, entity, worker_event

      before_each(function()
        stub(databus.queue, "add")

        worker_event = {
          data = { some = "data" },
          event = "some_event",
          source = "some_source",
          pid = 1234,
        }

        handler = "some_handler"
        handler_cb = function(data, event, source, pid) end
        stub(databus.handlers, handler).returns(handler_cb)

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
        databus.callback(entity)(worker_event.data,
                                 worker_event.event,
                                 worker_event.source,
                                 worker_event.pid)
        local blob = {
          callback = handler_cb,
          data = worker_event.data,
          event = worker_event.event,
          source = worker_event.source,
          pid = worker_event.pid,
        }

        assert.stub(databus.queue.add).was.called_with(databus.queue, blob)
      end)

      describe("on_change", function()
        it("when false, enqueues dbus job as many times as called", function()
          entity.on_change = false
          databus.callback(entity)(worker_event.data,
                                   worker_event.event,
                                   worker_event.source,
                                   worker_event.pid)
          assert.stub(databus.queue.add).was.called(1)

          databus.callback(entity)(worker_event.data,
                                   worker_event.event,
                                   worker_event.source,
                                   worker_event.pid)
          assert.stub(databus.queue.add).was.called(2)
        end)
        it("when true, enqueues dbus job only if data signature has changed", function()
          entity.on_change = true
          databus.callback(entity)(worker_event.data,
                                   worker_event.event,
                                   worker_event.source,
                                   worker_event.pid)
          assert.stub(databus.queue.add).was.called(1)

          databus.callback(entity)(worker_event.data,
                                   worker_event.event,
                                   worker_event.source,
                                   worker_event.pid)
          assert.stub(databus.queue.add).was.called(1)

          worker_event.data = { different = "data" }
          databus.callback(entity)(worker_event.data,
                                   worker_event.event,
                                   worker_event.source,
                                   worker_event.pid)
          assert.stub(databus.queue.add).was.called(2)

          worker_event.data = { different = "data" }
          databus.callback(entity)(worker_event.data,
                                   worker_event.event,
                                   worker_event.source,
                                   worker_event.pid)
          assert.stub(databus.queue.add).was.called(2)
        end)
      end)

      describe("snooze", function()
        it("when set, disables a databus event for 'snooze' seconds", function()
          entity.snooze = 60

          databus.callback(entity)(worker_event.data,
                                   worker_event.event,
                                   worker_event.source,
                                   worker_event.pid)
          assert.stub(databus.queue.add).was.called(1)

          databus.callback(entity)(worker_event.data,
                                   worker_event.event,
                                   worker_event.source,
                                   worker_event.pid)
          assert.stub(databus.queue.add).was.called(1)

          -- 50 seconds pass
          kong.cache._travel(50)
          databus.callback(entity)(worker_event.data,
                                   worker_event.event,
                                   worker_event.source,
                                   worker_event.pid)
          assert.stub(databus.queue.add).was.called(1)

          -- 20 more seconds pass (70 seconds)
          kong.cache._travel(20)
          databus.callback(entity)(worker_event.data,
                                   worker_event.event,
                                   worker_event.source,
                                   worker_event.pid)
          assert.stub(databus.queue.add).was.called(2)

          -- now it should be snoozed for 60 more seconds (130 seconds)
          -- 30 seconds pass
          kong.cache._travel(30)
          databus.callback(entity)(worker_event.data,
                                   worker_event.event,
                                   worker_event.source,
                                   worker_event.pid)
          assert.stub(databus.queue.add).was.called(2)

          -- 31 seconds pass
          kong.cache._travel(31)
          databus.callback(entity)(worker_event.data,
                                   worker_event.event,
                                   worker_event.source,
                                   worker_event.pid)
          assert.stub(databus.queue.add).was.called(3)
        end)
      end)

      describe("on_change + snooze", function()
        it("only events with different signatures get called during snooze time", function()
          entity.on_change = true
          entity.snooze = 60

          local different_data = { different = "data" }

          -- first event
          databus.callback(entity)(worker_event.data,
                                   worker_event.event,
                                   worker_event.source,
                                   worker_event.pid)
          assert.stub(databus.queue.add).was.called(1)

          -- 10 seconds
          kong.cache._travel(10)

          -- same as first
          databus.callback(entity)(worker_event.data,
                                   worker_event.event,
                                   worker_event.source,
                                   worker_event.pid)
          assert.stub(databus.queue.add).was.called(1)

          -- different data
          databus.callback(entity)(different_data,
                                   worker_event.event,
                                   worker_event.source,
                                   worker_event.pid)
          assert.stub(databus.queue.add).was.called(2)

          -- 20 seconds
          kong.cache._travel(10)

          -- different data
          databus.callback(entity)(different_data,
                                   worker_event.event,
                                   worker_event.source,
                                   worker_event.pid)
          assert.stub(databus.queue.add).was.called(2)

          -- 61 seconds
          kong.cache._travel(41)

          -- first event
          databus.callback(entity)(worker_event.data,
                                   worker_event.event,
                                   worker_event.source,
                                   worker_event.pid)
          assert.stub(databus.queue.add).was.called(3)

          -- different data
          databus.callback(entity)(worker_event.data,
                                   worker_event.event,
                                   worker_event.source,
                                   worker_event.pid)
          assert.stub(databus.queue.add).was.called(3)

          -- 71 seconds
          kong.cache._travel(71)

          databus.callback(entity)(worker_event.data,
                                   worker_event.event,
                                   worker_event.source,
                                   worker_event.pid)
          assert.stub(databus.queue.add).was.called(4)
        end)
      end)
    end)

    describe("[lambda]", function()

    end)

    describe("[webhook]", function()
      describe("makes a request", function()
        local entity
        local handler = databus.handlers.webhook

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

        it("to an url with a method", function()
          entity.config = {
            url = "http://foobar.com",
            method = "GET",
          }
          local cb = handler(entity, entity.config)
          cb({ some = "data"}, "some_event", "some_source", 1234)
          assert.stub(request).was.called_with(entity.config.url, {
            method = entity.config.method,
          })

          entity.config = {
            url = "http://foobar.com",
            method = "POST",
          }
          local cb = handler(entity, entity.config)
          cb({ some = "data"}, "some_event", "some_source", 1234)
          assert.stub(request).was.called_with(entity.config.url, {
            method = entity.config.method,
          })
        end)

        -- request responsability to do something with it
        describe("payload and payload_format", function()
          it("sends payload as a table", function()
            entity.config = {
              url = "http://foobar.com",
              method = "POST",
              payload = {
                some = "params",
                to = "convert",
                as_a = "body",
                -- but it's not our problem
              }
            }
            local cb = handler(entity, entity.config)
            cb({ some = "data"}, "some_event", "some_source", 1234)
            assert.stub(request).was.called_with(entity.config.url, {
              method = entity.config.method,
              data = entity.config.payload,
            })
          end)

          it("payload gets formatted", function()
            entity.config = {
              url = "http://foobar.com",
              method = "POST",
              payload_format = true,
              payload = {
                this_one = "is formatted with {{ some }}",
                -- but it's not our problem
              }
            }
            local cb = handler(entity, entity.config)
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
              url = "http://foobar.com",
              method = "POST",
              body = [[
               { "some": "arbitrary body" }
              ]],
            }
            local cb = handler(entity, entity.config)
            cb({ some = "data"}, "some_event", "some_source", 1234)
            assert.stub(request).was.called_with(entity.config.url, {
              method = entity.config.method,
              body = entity.config.body,
            })
          end)

          it("body gets formatted", function()
            entity.config = {
              url = "http://foobar.com",
              method = "POST",
              body_format = true,
              body = [[
                { "some {{ some }}": "arbitrary body {{ some }}" }
              ]]
            }
            local cb = handler(entity, entity.config)
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
              url = "http://foobar.com",
              method = "POST",
              secret = "hunter2",
            }
            local cb = handler(entity, entity.config)
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
              url = "http://foobar.com",
              method = "GET",
              headers = {
                ["X-Give-Me"] = "some tests",
              },
            }
            local cb = handler(entity, entity.config)
            cb({ some = "data"}, "some_event", "some_source", 1234)
            assert.stub(request).was.called_with(entity.config.url, {
              method = entity.config.method,
              headers = entity.config.headers,
            })
          end)

          it("headers can be formatted with data", function()
            entity.config = {
              url = "http://foobar.com",
              method = "GET",
              headers = {
                ["X-Give-Me"] = "some tests {{ some }}",
              },
              headers_format = true,
            }
            local cb = handler(entity, entity.config)
            cb({ some = "data"}, "some_event", "some_source", 1234)
            assert.stub(request).was.called_with(entity.config.url, {
              method = entity.config.method,
              headers = {
                ["X-Give-Me"] = "some tests data",
              },
            })
          end)
        end)
      end)
    end)

    describe("[log]", function()

    end)
  end)
end)
