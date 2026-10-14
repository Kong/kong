local mocker = require("spec.fixtures.mocker")


local function setup_it_block()

  -- keep track of created semaphores
  local semaphores = {}

  local my_cache = {}

  mocker.setup(finally, {

    ngx = {
      log = function()
        -- avoid stdout output during test
      end,
      timer = {
        at = function() end,
        every = function() end,
      },
      var = {
      },
    },

    kong = {
      timer = _G.timerng,
      log = {
        err = function() end,
        warn = function() end,
      },
      response = {
        error = function() end,
      },
      worker_events = {
        register = function() end,
      },
      cluster_events = {
        subscribe = function() end,
      },
      configuration = {
        database = "dummy",
        worker_consistency = "strict",
      },
      db = {
        strategy = "dummy",
      },
      core_cache = {
        _cache = my_cache,
        get = function(_, k)
          return my_cache[k] or "1"
        end
      }
    },

    modules = {
      { "kong.runloop.balancer", {
        init = function() end
      }},

      { "ngx.semaphore",  {
        _semaphores = semaphores,
        new = function()
          local s = {
            value = 0,
            wait = function(self, timeout)
              self.value = self.value - 1
              return true
            end,
            post = function(self, n)
              n = n or 1
              self.value = self.value + n
              return true
            end,
          }
          table.insert(semaphores, s)
          return s
        end,
      }},

      { "kong.concurrency", {} },

      { "kong.runloop.handler", {} },

      { "kong.runloop.events", {} },

    }

  })
end


local mock_router = {
  exec = function()
    return nil
  end
}


local function setup_router_snapshot_it_block()
  local state = {
    db_available = true,
    db_each_calls = 0,
    phase = "timer",
  }

  local snapshot_values = {}
  local shared = setmetatable({
    kong = {
      incr = function()
        return 1
      end,
    },
    kong_core_db_cache = {
      get = function(_, key)
        return snapshot_values[key]
      end,
      safe_set = function(_, key, value)
        snapshot_values[key] = value
        return true
      end,
    },
  }, {
    __index = ngx.shared,
  })

  local route = {
    id = "current-route",
    paths = { "/current" },
    protocols = { "http" },
  }

  local Router = {
    DEFAULT_MATCH_LRUCACHE_SIZE = 100,
    new = function(routes)
      return {
        exec = function()
          return nil
        end,
        routes = routes,
      }
    end,
  }

  mocker.setup(finally, {
    ngx = {
      get_phase = function()
        return state.phase
      end,
      log = function() end,
      shared = shared,
    },

    kong = {
      configuration = {
        database = "postgres",
        worker_consistency = "eventual",
      },
      core_cache = {
        get = function()
          return "current-version"
        end,
      },
      db = {
        strategy = "postgres",
        routes = {
          pagination = {
            max_page_size = 1000,
          },
          each = function()
            state.db_each_calls = state.db_each_calls + 1
            local done

            return function()
              if done then
                return nil
              end

              done = true
              if not state.db_available then
                return false, "database unavailable"
              end

              return route
            end
          end,
        },
      },
    },

    modules = {
      { "kong.router", Router },
      { "kong.runloop.handler", {} },
    },
  })

  return state
end


describe("runloop handler", function()
  describe("router rebuilds", function()

    it("releases the lock when rebuilding the router fails", function()
      setup_it_block()

      local semaphores = require "ngx.semaphore"._semaphores
      local handler = require "kong.runloop.handler"

      local update_router_spy = spy.new(function()
        return nil, "error injected by test (feel free to ignore :) )"
      end)

      handler.init_worker.before({})

      handler._set_router(mock_router)
      handler._set_update_router(update_router_spy)

      handler.access.before({})

      assert.spy(update_router_spy).was_called(1)

      -- check semaphore
      assert.equal(1, semaphores[1].value)
    end)

    it("bypasses router_semaphore upon acquisition timeout", function()
      setup_it_block()

      local semaphores = require "ngx.semaphore"._semaphores
      local handler = require "kong.runloop.handler"

      handler.init_worker.before()

      local update_router_spy = spy.new(function() end)
      handler._set_update_router(update_router_spy)
      handler._set_router(mock_router)

      -- call it once to create a semaphore
      handler.access.before({})

      assert.spy(update_router_spy).was_called(1)

      -- force a router rebuild
      handler._set_router_version("old")

      -- cause failure to acquire semaphore
      semaphores[1].wait = function()
        return nil, "timeout"
      end

      handler.access.before({})

      -- was called even if semaphore timed out on acquisition
      assert.spy(update_router_spy).was_called(2)

      -- check semaphore
      assert.equal(1, semaphores[1].value)
    end)

    it("does not call update_router if worker_consistency is eventual", function()
      setup_it_block()

      kong.configuration.worker_consistency = "eventual"

      local handler = require "kong.runloop.handler"

      local update_router_spy = spy.new(function() end)
      handler._set_update_router(update_router_spy)
      handler._set_router(mock_router)

      handler.init_worker.before()

      handler.access.before({})

      assert.spy(update_router_spy).was_called(0)
      assert.equal(mock_router, handler._get_updated_router())
    end)

    it("does not call register_balancer_events if role is control_plane", function()
      setup_it_block()

      kong.configuration.role = "control_plane"

      local handler = require "kong.runloop.handler"
      local events  = require "kong.runloop.events"

      local register_balancer_events_spy = spy.new(function() end)

      handler._set_router(mock_router)

      events._register_balancer_events(register_balancer_events_spy)

      handler.init_worker.before()

      assert.spy(register_balancer_events_spy).was_called(0)
    end)

    it("call register_balancer_events if role is data_plane", function()
      setup_it_block()

      kong.configuration.role = "data_plane"

      local handler = require "kong.runloop.handler"
      local events  = require "kong.runloop.events"

      local register_balancer_events_spy = spy.new(function() end)

      handler._set_router(mock_router)

      events._register_balancer_events(register_balancer_events_spy)

      handler.init_worker.before()

      assert.spy(register_balancer_events_spy).was_called(1)
    end)

    it("calls build_router if router version changes and worker_consistency is strict", function()
      setup_it_block()

      kong.configuration.worker_consistency = "strict"

      local handler = require "kong.runloop.handler"

      local latest_router

      local build_router_spy = spy.new(function()
        handler._set_router_version(kong.core_cache:get("router:version"))
        latest_router = {
          exec = function()
            return nil
          end
        }
        handler._set_router(latest_router)
      end)
      handler._set_build_router(build_router_spy)

      handler.init_worker.before()

      handler.access.before({})

      assert.spy(build_router_spy).was_called(1)
      assert.equal(latest_router, handler._get_updated_router())

      local saved_router = latest_router

      kong.core_cache._cache["router:version"] = "new_version"

      handler.access.before({})

      assert.spy(build_router_spy).was_called(2)
      assert.equal(latest_router, handler._get_updated_router())
      assert.not_equal(saved_router, latest_router)
    end)

    it("does not call build_router if router version does not change and worker_consistency is strict", function()
      setup_it_block()

      kong.configuration.worker_consistency = "strict"

      local handler = require "kong.runloop.handler"

      local latest_router

      local build_router_spy = spy.new(function()
        handler._set_router_version(kong.core_cache:get("router:version"))
        latest_router = {
          exec = function()
            return nil
          end
        }
        handler._set_router(latest_router)
      end)
      handler._set_build_router(build_router_spy)
      handler._set_router(mock_router)

      handler.init_worker.before()

      handler.access.before({})

      assert.spy(build_router_spy).was_called(1)
      assert.equal(latest_router, handler._get_updated_router())

      local saved_router = latest_router

      handler.access.before({})

      assert.spy(build_router_spy).was_called(1)
      assert.equal(saved_router, latest_router)
    end)

  end)
end)


describe("runloop handler router snapshots", function()
  it("rebuilds a respawned worker from the current snapshot", function()
    local state = setup_router_snapshot_it_block()
    local handler = require "kong.runloop.handler"

    assert(handler.build_router("current-version"))
    assert.equal(1, state.db_each_calls)

    state.db_available = false
    state.db_each_calls = 0
    state.phase = "init_worker"
    handler._set_router({ stale = true })

    assert(handler.build_router("current-version"))
    assert.equal(0, state.db_each_calls)

    local router = handler._get_updated_router()
    assert.equal("/current", router.routes[1].route.paths[1])
    assert.is_nil(router.stale)
  end)

  it("does not use an inherited router when the snapshot is outdated", function()
    local state = setup_router_snapshot_it_block()
    local handler = require "kong.runloop.handler"

    assert(handler.build_router("current-version"))

    state.db_available = false
    state.db_each_calls = 0
    state.phase = "init_worker"
    handler._set_router({ stale = true })

    local ok, err = handler.build_router("new-version")
    assert.is_nil(ok)
    assert.matches("database unavailable", err, nil, true)
    assert.equal(1, state.db_each_calls)

    local router = handler._get_updated_router()
    assert.equal(0, #router.routes)
    assert.is_nil(router.stale)
  end)
end)
