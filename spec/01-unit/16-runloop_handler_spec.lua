local mocker = require("spec.fixtures.mocker")


local function setup_it_block()

  -- keep track of created semaphores
  local semaphores = {}

  mocker.setup(finally, {

    ngx = {
      log = function()
        -- avoid stdout output during test
      end,
    },

    kong = {
      log = {
        err = function() end,
        warn = function() end,
      },
      response = {
        exit = function() end,
      },
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
        cache = {
          get = function()
            return "1"
          end
        }
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

describe("runloop handler", function()
  describe("router rebuilds", function()

    it("releases the lock when rebuilding the router fails", function()
      setup_it_block()

      local semaphores = require "ngx.semaphore"._semaphores
      local handler = require "kong.runloop.handler"

      local check_router_rebuild_spy = spy.new(function()
        return nil, "error injected by test (feel free to ignore :) )"
      end)

      handler._set_check_router_rebuild(check_router_rebuild_spy)

      handler.access.before({})

      assert.spy(check_router_rebuild_spy).was_called(1)

      -- check semaphore
      assert.equal(1, semaphores[1].value)
    end)

    it("bypasses router_semaphore upon acquisition timeout", function()
      setup_it_block()

      local semaphores = require "ngx.semaphore"._semaphores
      local handler = require "kong.runloop.handler"

      local check_router_rebuild_spy = spy.new(function()
        return handler.check_router_rebuild()
      end)

      handler._set_check_router_rebuild(check_router_rebuild_spy)

      handler.access.before({})

      -- check semaphore
      assert.equal(1, semaphores[1].value)

      -- was called even if semaphore timed out on acquisition
      assert.spy(check_router_rebuild_spy).was_called(1)

      -- cause failure to acquire semaphore
      semaphores[1].wait = function()
        return nil, "timeout"
      end

      handler.access.before({})

      -- was called even if semaphore timed out on acquisition
      assert.spy(check_router_rebuild_spy).was_called(2)

      -- check semaphore
      assert.equal(1, semaphores[1].value)
    end)

  end)
end)
