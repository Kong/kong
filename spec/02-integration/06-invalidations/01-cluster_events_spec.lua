_G.ngx.config.debug = true


local helpers             = require "spec.helpers"
local kong_cluster_events = require "kong.cluster_events"
local match               = require "luassert.match"


for _, strategy in helpers.each_strategy() do
  describe("cluster_events with db [#" .. strategy .. "]", function()
    local db, log_spy, orig_ngx_log

    lazy_setup(function()
      local _
      _, db = helpers.get_db_utils(strategy, {})

      orig_ngx_log = ngx.log
      local logged = { level = function() end }
      log_spy = spy.on(logged, "level")
      _G.ngx.log = function(l) logged.level(l) end   -- luacheck: ignore
    end)

    lazy_teardown(function()
      local cluster_events = assert(kong_cluster_events.new { db = db })
      cluster_events.strategy:truncate_events()

      _G.ngx.log = orig_ngx_log   -- luacheck: ignore
    end)

    before_each(function()
      ngx.shared.kong:flush_all()
      ngx.shared.kong:flush_expired()
      ngx.shared.kong_cluster_events:flush_all()
      ngx.shared.kong_cluster_events:flush_expired()

      local cluster_events = assert(kong_cluster_events.new { db = db })
      cluster_events.strategy:truncate_events()
    end)

    describe("new()", function()
      it("creates an instance", function()
        local cluster_events, err = kong_cluster_events.new { db = db }
        assert.is_nil(err)
        assert.is_table(cluster_events)
      end)

      it("instantiates only once (singleton)", function()
        finally(function()
          _G.ngx.config.debug = true
          package.loaded["kong.cluster_events"] = nil
          kong_cluster_events = require "kong.cluster_events"
        end)

        _G.ngx.config.debug = false
        package.loaded["kong.cluster_events"] = nil
        kong_cluster_events = require "kong.cluster_events"

        assert(kong_cluster_events.new { db = db })

        assert.has_error(function()
          assert(kong_cluster_events.new { db = db })
        end, "kong.cluster_events was already instantiated", nil, true)
      end)

      it("generates an identical node_id for all instances on a node", function()
        local cluster_events_1 = assert(kong_cluster_events.new {
          db = db,
        })

        local cluster_events_2 = assert(kong_cluster_events.new {
          db = db,
        })

        assert.is_string(cluster_events_1.node_id)
        assert.equal(cluster_events_1.node_id, cluster_events_2.node_id)
      end)

      it("instantiates but does not start polling", function()
        local cluster_events = assert(kong_cluster_events.new { db = db })
        assert.is_false(cluster_events.polling)
      end)
    end)

    describe("pub/sub", function()
      local spy_func
      local uuid_1 = "a1e04ff0-3416-11e7-ba48-784f437104fa"
      local uuid_2 = "bbbd53dc-3416-11e7-aea6-784f437104fa"
      local cb = function(...)
        spy_func(...)
      end

      before_each(function()
        spy_func = spy.new(function() end)
        -- time sensitive tests should have accurate time at the start
        -- and for the later `ngx.sleep()` calls the time will be updated automatically
        ngx.update_time()
      end)

      it("broadcasts on a given channel", function()
        -- nodes must not have the same node_id, to mimic 2 different Kong nodes
        -- on a cluster
        local cluster_events_1 = assert(kong_cluster_events.new {
          db = db,
          node_id = uuid_1
        })

        local cluster_events_2 = assert(kong_cluster_events.new {
          db = db,
          node_id = uuid_2
        })

        assert(cluster_events_1:subscribe("my_channel", cb, false))
        assert(cluster_events_1:subscribe("my_other_channel", cb, false))

        assert(cluster_events_2:broadcast("my_channel", "hello world"))
        assert.spy(spy_func).was_not_called()

        assert(cluster_events_1:poll())
        assert.spy(spy_func).was_called(1)

        assert(cluster_events_2:broadcast("my_channel", "hello world"))
        assert.spy(spy_func).was_called(1)

        assert(cluster_events_1:poll())
        assert.spy(spy_func).was_called(2)

        assert(cluster_events_2:broadcast("my_other_channel", "hello world"))
        assert.spy(spy_func).was_called(2)

        assert(cluster_events_1:poll())
        assert.spy(spy_func).was_called(3)
        assert.spy(log_spy).was_not_called_with(match.is_not.gt(ngx.ERR))
      end)

      it("broadcasts data to subscribers", function()
        -- nodes must not have the same node_id, to mimic 2 different Kong nodes
        -- on a cluster
        local cluster_events_1 = assert(kong_cluster_events.new {
          db = db,
          node_id = uuid_1,
        })

        local cluster_events_2 = assert(kong_cluster_events.new {
          db = db,
          node_id = uuid_2,
        })

        assert(cluster_events_1:subscribe("my_channel", cb, false))

        assert(cluster_events_2:broadcast("my_channel", "hello world"))
        assert.spy(spy_func).was_not_called()

        assert(cluster_events_1:poll())
        assert.spy(spy_func).was_called(1)
        assert.spy(spy_func).was_called_with("hello world")
        assert.spy(log_spy).was_not_called_with(match.is_not.gt(ngx.ERR))
      end)

      it("does not broadcast events on the same node", function()
        -- same node_id
        local cluster_events_1 = assert(kong_cluster_events.new {
          db = db,
          node_id = uuid_1,
        })

        local cluster_events_2 = assert(kong_cluster_events.new {
          db = db,
          node_id = uuid_1,
        })

        assert(cluster_events_1:subscribe("my_channel", cb, false))

        assert(cluster_events_2:broadcast("my_channel", "hello world"))
        assert.spy(spy_func).was_not_called()

        assert(cluster_events_1:poll())
        assert.spy(spy_func).was_not_called()
        assert.spy(log_spy).was_not_called_with(match.is_not.gt(ngx.ERR))
      end)

      it("starts interval polling when subscribing", function()
        local cluster_events_1 = assert(kong_cluster_events.new {
          db = db,
          poll_interval = 0.3,
          node_id       = uuid_1
        })

        local cluster_events_2 = assert(kong_cluster_events.new {
          db = db,
          node_id = uuid_2
        })

        finally(function()
          cluster_events_1.polling = false
          ngx.sleep(0.4)
        end)

        local called = 0

        assert(cluster_events_1:subscribe("my_channel", function() called = called + 1 end))

        assert(cluster_events_2:broadcast("my_channel", "hello world"))
        assert.equal(0, called)
        helpers.wait_until(function()
          return called == 1
        end, 10)

        assert(cluster_events_2:broadcast("my_channel", "hello world"))
        assert.equal(1, called)
        helpers.wait_until(function()
          return called == 2
        end, 10)
        assert.spy(log_spy).was_not_called_with(match.is_not.gt(ngx.ERR))
      end)

      it("applies a poll_offset to lookback potentially missed events", function()
        local cluster_events_1 = assert(kong_cluster_events.new {
          db = db,
          node_id     = uuid_1,
          poll_offset = 2,
        })

        local cluster_events_2 = assert(kong_cluster_events.new {
          db = db,
          node_id     = uuid_2,
          poll_offset = 2,
        })

        assert(cluster_events_1:subscribe("grace_period_channel", cb, false))

        assert(cluster_events_2:broadcast("grace_period_channel", "hello world"))
        assert.spy(spy_func).was_not_called()

        assert(cluster_events_1:poll())
        assert.spy(spy_func).was_called(1)

        -- only called once
        assert(cluster_events_1:poll())
        assert.spy(spy_func).was_called(1)

        -- reset shm storing ran events
        cluster_events_1.events_shm:flush_all()
        cluster_events_1.events_shm:flush_expired()

        ngx.sleep(1)

        -- ran again because of the lookback
        assert(cluster_events_1:poll())
        assert.spy(spy_func).was_called(2) -- was effectively called again

        ngx.sleep(1.001) -- 2.001 > poll_offset (2)

        assert(cluster_events_1:poll())
        assert.spy(spy_func).was_called(2) -- not called again this time
        assert.spy(log_spy).was_not_called_with(match.is_not.gt(ngx.ERR))
      end)

      it("handles more than <PAGE_SIZE> events at once", function()
        local cluster_events_1 = assert(kong_cluster_events.new {
          db = db,
          node_id = uuid_1,
        })

        local cluster_events_2 = assert(kong_cluster_events.new {
          db = db,
          node_id = uuid_2,
        })

        assert(cluster_events_1:subscribe("busy_channel", cb, false))

        -- default page size is 100

        for i = 1, 201 do
          assert(cluster_events_2:broadcast("busy_channel", "hello world"))
        end

        assert(cluster_events_1:poll())
        assert.spy(spy_func).was_called(201)
        assert.spy(log_spy).was_not_called_with(match.is_not.gt(ngx.ERR))
      end)

      it("runs callbacks in protected mode", function()
        local cluster_events_1 = assert(kong_cluster_events.new {
          db = db,
          node_id = uuid_1,
        })

        local cluster_events_2 = assert(kong_cluster_events.new {
          db = db,
          node_id = uuid_2,
        })

        assert(cluster_events_1:subscribe("errors_channel", function()
          error("foo")
        end, false)) -- false to not start auto polling

        assert(cluster_events_2:broadcast("errors_channel", "hello world"))

        assert.has_no_error(function()
          cluster_events_1:poll()
        end)
        assert.spy(log_spy).was_not_called_with(match.is_not.gt(ngx.ERR))
      end)

      it("broadcasts an event with a delay", function()
        ngx.update_time()
        local cluster_events_1 = assert(kong_cluster_events.new {
          db = db,
          node_id = uuid_1,
        })

        local cluster_events_2 = assert(kong_cluster_events.new {
          db = db,
          node_id = uuid_2,
        })

        assert(cluster_events_1:subscribe("nbf_channel", cb, false)) -- false to not start auto polling

        local delay = 1

        assert(cluster_events_2:broadcast("nbf_channel", "hello world", delay))

        assert(cluster_events_1:poll())
        assert.spy(spy_func).was_not_called() -- not called yet

        ngx.sleep(0.001) -- still yield in case our timer is set to 0

        assert(cluster_events_1:poll())
        assert.spy(spy_func).was_not_called() -- still not called

        ngx.sleep(delay) -- go past our desired `nbf` delay

        helpers.wait_until(function()
          assert(cluster_events_1:poll())
          return pcall(assert.spy(spy_func).was_called, 1) -- called
        end, 1) -- note that we have already waited for `delay` seconds
        assert.spy(log_spy).was_not_called_with(match.is_not.gt(ngx.ERR))
      end)

      it("broadcasts an event with a polling delay for subscribers", function()
        local delay = 1

        local cluster_events_1 = assert(kong_cluster_events.new {
          db = db,
          node_id = uuid_1,
          poll_delay = delay,
        })

        local cluster_events_2 = assert(kong_cluster_events.new {
          db = db,
          node_id = uuid_2,
          poll_delay = delay,
        })

        assert(cluster_events_1:subscribe("nbf_channel", cb, false)) -- false to not start auto polling

        -- we need accurate time, otherwise the test would be flaky
        ngx.update_time()
        assert(cluster_events_2:broadcast("nbf_channel", "hello world"))

        assert(cluster_events_1:poll())
        assert.spy(spy_func).was_not_called() -- not called yet

        ngx.sleep(0.001) -- still yield in case our timer is set to 0

        assert(cluster_events_1:poll())
        assert.spy(spy_func).was_not_called() -- still not called

        ngx.sleep(delay) -- go past our desired `nbf` delay

        helpers.wait_until(function()
          assert(cluster_events_1:poll())
          return pcall(assert.spy(spy_func).was_called, 1) -- called
        end, 1) -- note that we have already waited for `delay` seconds
        assert.spy(log_spy).was_not_called_with(match.is_not.gt(ngx.ERR))
      end)
    end)
  end)
end
