-- local utils = require "kong.tools.utils"

describe("databus", function()

  local databus = require "kong.enterprise_edition.databus"

  -- reset any mocks, stubs, whatever was messed up on _G.kong and databus
  before_each(function()
    _G.kong = {
      configuration = {
        databus_enabled = true,
      },
      worker_events = {},
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
          signature = { "foo" },
        }))
      end)
    end)

    it("publish stores them, and list lists them", function()
      assert(databus.publish("some_source", "some_event", {
          description = "Some event that does something",
          fields = { "foo", "bar" },
          signature = { "foo" },
      }))
      assert(databus.publish("another_source", "another_event"))
      local expected = {
        some_source = {
          some_event = {
            description = "Some event that does something",
            fields = { "foo", "bar" },
            signature = { "foo" },
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
      it("with a callback, a source (prefixed by dbus:) and an event", function()
        databus.register(some_entity)
        assert.stub(kong.worker_events.register)
              .was.called_with(mock_function, "dbus:some_source", "some_event")
      end)
      it("an entity can have a nil event", function()
        some_entity.event = nil
        databus.register(some_entity)
        assert.stub(kong.worker_events.register)
              .was.called_with(mock_function, "dbus:some_source", nil)
      end)
      it("an entity can have a ngx.null event that is nil too", function()
        some_entity.event = ngx.null
        databus.register(some_entity)
        assert.stub(kong.worker_events.register)
              .was.called_with(mock_function, "dbus:some_source", nil)
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
      it("with the original callback, a source (prefixed by dbus:) and an event", function()
        databus.register(some_entity)
        stub(databus, "callback").returns(function() end)
        databus.unregister(some_entity)
        assert.stub(kong.worker_events.unregister)
              .was.called_with(mock_function, "dbus:some_source", "some_event")
      end)
      it("an entity can have a nil event", function()
        some_entity.event = nil
        databus.register(some_entity)
        stub(databus, "callback").returns(function() end)
        databus.unregister(some_entity)
        assert.stub(kong.worker_events.unregister)
              .was.called_with(mock_function, "dbus:some_source", nil)
      end)
      it("an entity can have a ngx.null event that is nil too", function()
        some_entity.event = ngx.null
        databus.register(some_entity)
        stub(databus, "callback").returns(function() end)
        databus.unregister(some_entity)
        assert.stub(kong.worker_events.unregister)
              .was.called_with(mock_function, "dbus:some_source", nil)
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
              .was.called_with("dbus:some_source", "some_event", { some = "data" })
      end)
    end)
  end)

  describe("signature", function()
    describe("generates the signature of a data message", function()
      it("defaults to the whole data when an event has not been published", function()
        local data = { some = "data", with_more = "data" }
        assert.equal("fcd3b17e549f0a83f5bd14aa85d2f2cb",
                     databus.signature("some_source", "some_event", data))
      end)

      it("two data messages have the same signature if their relevant fields are the same", function()
        local source = "some_source"
        local event = "some_event"
        local data = { some = "data", with_more = "data", and_more = "data" }
        local more_data = { some = "data", with_more = "data", and_more = "snowflake" }

        databus.publish("some_source", "some_event", {
             description = "Some event that does something",
             fields = { "some", "with_more", "and_more" },
             signature = { "some", "with_more" },
        })
        assert.equal("fcd3b17e549f0a83f5bd14aa85d2f2cb",
                     databus.signature(source, event, data))
        assert.equal(databus.signature(source, event, more_data),
                     databus.signature(source, event, data))
      end)

      it("changes the signature when a relevant field changes", function()
        local source = "some_source"
        local event = "some_event"
        local data = { some = "data", with_more = "data", and_more = "data" }
        local more_data = { some = "data", with_more = "snowflake", and_more = "snowflake" }

        databus.publish("some_source", "some_event", {
             description = "Some event that does something",
             fields = { "some", "with_more", "and_more" },
             signature = { "some", "with_more" },
        })
        assert.not_equal(databus.signature(source, event, more_data),
                     databus.signature(source, event, data))
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

      -- databus callback needs the source without the prefix to be able and
      -- find it on the events list and try to find relevant fields for
      -- on_change and snooze
      it("':dbus' is removed from the source", function()
        databus.callback(entity)(worker_event.data,
                                 worker_event.event,
                                 "dbus:" .. worker_event.source,
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
    end)
  end)
end)
