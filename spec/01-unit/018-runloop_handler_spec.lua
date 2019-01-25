local function setup_it_block()
  local mocked_modules = {}
  local _ngx = _G.ngx

  local function mock_module(name, tbl)
    local old_module = require(name)
    mocked_modules[name] = true
    package.loaded[name] = setmetatable(tbl or {}, {
      __index = old_module,
    })
  end

  _G.ngx = setmetatable({
    log = function()
      -- avoid stdout output during test
    end,
  }, { __index = _ngx })

  finally(function()
    _G.ngx = _ngx

    for k in pairs(mocked_modules) do
      package.loaded[k] = nil
    end
  end)

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
    cache = {
      get = function()
        return "1"
      end
    }
  })

  mock_module("kong.runloop.balancer", {
    init = function() end
  })

  -- FIXME remove kong.tools.responses {{{
  mock_module("kong.tools.responses", {
    send_HTTP_INTERNAL_SERVER_ERROR = function() end,
  })
  -- FIXME }}}

  -- keep track of created semaphores
  local semaphores = {}

  mock_module("ngx.semaphore", {
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
  })

  mock_module("kong.runloop.handler")
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

      handler.init_worker.before()

      -- check semaphore
      assert.equal(1, semaphores[1].value)
      -- FIXME remove apis {{{
      assert.equal(1, semaphores[2].value)
      -- FIXME }}}

      handler.access.before({})

      assert.spy(check_router_rebuild_spy).was_called(1)

      -- check semaphore
      assert.equal(1, semaphores[1].value)
      -- FIXME remove apis {{{
      assert.equal(1, semaphores[2].value)
      -- FIXME }}}
    end)

    it("bypasses router_semaphore upon acquisition timeout", function()
      setup_it_block()

      local semaphores = require "ngx.semaphore"._semaphores
      local handler = require "kong.runloop.handler"

      local check_router_rebuild_spy = spy.new(function()
        return handler.check_router_rebuild()
      end)

      handler._set_check_router_rebuild(check_router_rebuild_spy)

      handler.init_worker.before()

      -- cause failure to acquire semaphore
      semaphores[2].wait = function()
        return nil, "timeout"
      end

      -- check semaphore
      assert.equal(1, semaphores[1].value)
      -- FIXME remove apis {{{
      assert.equal(1, semaphores[2].value)
      -- FIXME }}}

      handler.access.before({})

      -- was called even if semaphore timed out on acquisition
      assert.spy(check_router_rebuild_spy).was_called(1)

      -- check semaphore
      assert.equal(1, semaphores[1].value)
      -- FIXME remove apis {{{
      assert.equal(1, semaphores[2].value)
      -- FIXME }}}
    end)

  end)
end)
