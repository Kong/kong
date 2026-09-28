local mocker = require "spec.fixtures.mocker"

local ws_id = require("kong.tools.uuid").uuid()

local UPSTREAM = {
  id = "f9e0cb43-7de6-4c73-a89a-5a1b0f4d9c2e",
  name = "partial-event-upstream",
  ws_id = ws_id,
}

local function setup_kong()
  local kong = {}

  _G.kong = kong

  kong.worker_events = require "resty.events.compat"
  kong.worker_events.configure({
    listening = "unix:",
    testing = true,
  })

  kong.db = {
    targets = {
      select_by_upstream_raw = function()
        return {}
      end,
    },
    upstreams = {
      select = function(_, pk)
        if pk.id == UPSTREAM.id then
          return UPSTREAM
        end
      end,
    },
  }

  kong.core_cache = {
    _cache = {},
    get = function(self, key, _, loader, arg)
      local v = self._cache[key]
      if v == nil then
        v = loader(arg)
        self._cache[key] = v
      end
      return v
    end,
    invalidate_local = function(self, key)
      self._cache[key] = nil
    end,
  }

  return kong
end

describe("[balancer target events]", function()
  local targets, balancers

  lazy_teardown(function()
    ngx.log:revert() -- luacheck: ignore
  end)

  lazy_setup(function()
    stub(ngx, "log")

    package.loaded["kong.runloop.balancer"] = nil
    package.loaded["kong.runloop.balancer.targets"] = nil
    package.loaded["kong.runloop.balancer.upstreams"] = nil
    package.loaded["kong.runloop.balancer.balancers"] = nil
    package.loaded["kong.runloop.balancer.healthcheckers"] = nil

    setup_kong()

    targets = require "kong.runloop.balancer.targets"
    balancers = require "kong.runloop.balancer.balancers"
  end)

  local function setup_it_block()
    mocker.setup(finally, {
      kong = {
        configuration = {
          worker_consistency = "eventual",
          worker_state_update_frequency = 0.1,
        },
      },
      ngx = {
        ctx = {
          workspace = ws_id,
        },
      },
    })
  end

  it("rebuilds the balancer on a partial delete event with an empty target cache", function()
    -- a delete event whose entity carries only the upstream reference cannot
    -- produce a DNS renewal key, and the worker-local target cache may be
    -- empty; the handler must still proceed to rebuild the balancer
    setup_it_block()

    stub(balancers, "get_balancer_by_id").returns({})
    stub(balancers, "create_balancer").returns({})

    finally(function()
      balancers.get_balancer_by_id:revert() -- luacheck: ignore
      balancers.create_balancer:revert() -- luacheck: ignore
    end)

    targets.clean_targets_cache(UPSTREAM)

    assert.has_no.errors(function()
      targets.on_target_event("delete", {
        upstream = { id = UPSTREAM.id, name = UPSTREAM.name },
      })
    end)

    assert.stub(balancers.create_balancer).was_called()
  end)
end)
