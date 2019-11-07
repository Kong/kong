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
      }
    },

    kong = {
      log = {
        err = function() end,
        warn = function() end,
      },
      response = {
        exit = function() end,
      },
      worker_events = {
        register = function() end,
      },
      cluster_events = {
        subscribe = function() end,
      },
      configuration = {
        database = "dummy",
        router_consistency = "strict",
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
      { "kong.singletons", {
        configuration = {
          database = "dummy",
        },
        worker_events = {
          register = function() end,
        },
        cluster_events = {
          subscribe = function() end,
        },
      }},

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

    }

  })
end


local mock_router = {
  exec = function()
    return nil
  end
}


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

    it("does not call update_router if router_consistency is eventual", function()
      setup_it_block()

      kong.configuration.router_consistency = "eventual"

      local handler = require "kong.runloop.handler"

      local update_router_spy = spy.new(function() end)
      handler._set_update_router(update_router_spy)
      handler._set_router(mock_router)

      handler.init_worker.before()

      handler.access.before({})

      assert.spy(update_router_spy).was_called(0)
      assert.equal(mock_router, handler._get_updated_router())
    end)

    it("calls build_router if router version changes and router_consistency is strict", function()
      setup_it_block()

      kong.configuration.router_consistency = "strict"

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

    it("does not call build_router if router version does not change and router_consistency is strict", function()
      setup_it_block()

      kong.configuration.router_consistency = "strict"

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
