describe("runloop handler", function()

  it("releases the lock when rebuilding the router fails", function()
    -- mock db
    local db = {
      routes = {}
    }

    local function mock_module(name, tbl)
      local old_module = require(name)
      package.loaded[name] = tbl
      finally(function()
        package.loaded[name] = old_module
      end)
    end

    mock_module("kong.singletons", {
      configuration = {
        database = "dummy",
      },
      worker_events = {
        register = function() end,
      },
      cluster_events = {
        subscribe = function() end,
      },
      -- FIXME remove apis {{{
      dao = {
        apis = {
          find_all = function() return {} end,
        }
      },
      -- FIXME }}}
      db = db,
      cache = {
        get = function()
          return "1"
        end
      }
    })

    mock_module("kong.runloop.balancer", {
      init = function() end
    })

    _G.kong = {
      log = {
        err = function() end,
      },
      response = {
        exit = function() end,
      }
    }

    -- keep track of created semaphores
    local semaphores = {}

    mock_module("ngx.semaphore", {
      new = function()
        local s = {
          value = 0,
          wait = function(self)
            self.value = self.value - 1
            return true
          end,
          post = function(self)
            self.value = self.value + 1
            return true
          end,
        }
        table.insert(semaphores, s)
        return s
      end
    })

    local handler = require "kong.runloop.handler"
    finally(function()
      -- unload module using mocked dependencies
      package.loaded["kong.runloop.handler"] = nil
    end)

    -- initialize building empty router
    db.routes.each = function()
      return function()
               return nil
             end
    end

    handler.init_worker.before()

    -- check semaphore
    assert.same(semaphores[1].value, 1)
    -- FIXME remove apis {{{
    assert.same(semaphores[2].value, 1)
    -- FIXME }}}

    -- this will cause rebuilding the router to fail
    db.routes.each = function()
      return function()
               return false, "error injected by test (feel free to ignore :) )"
             end
    end

    handler.access.before({})

    -- check semaphore
    assert.same(semaphores[1].value, 1)
    -- FIXME remove apis {{{
    assert.same(semaphores[2].value, 1)
    -- FIXME }}}
  end)

end)
