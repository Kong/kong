local utils = require "kong.tools.utils"
local mocker = require "spec.fixtures.mocker"

local ws_id = utils.uuid()

local function setup_it_block(consistency)
  local cache_table = {}

  local function mock_cache(cache_table, limit)
    return {
      safe_set = function(self, k, v)
        if limit then
          local n = 0
          for _, _ in pairs(cache_table) do
            n = n + 1
          end
          if n >= limit then
            return nil, "no memory"
          end
        end
        cache_table[k] = v
        return true
      end,
      get = function(self, k, _, fn, arg)
        if cache_table[k] == nil then
          cache_table[k] = fn(arg)
        end
        return cache_table[k]
      end,
    }
  end

  mocker.setup(finally, {
    kong = {
      configuration = {
        worker_consistency = consistency,
        worker_state_update_frequency = 0.1,
      },
      core_cache = mock_cache(cache_table),
    },
    ngx = {
      ctx = {
        workspace = ws_id,
      }
    }
  })
end

for _, consistency in ipairs({"strict", "eventual"}) do
  describe("Balancer (worker_consistency = " .. consistency .. ")", function()
    local singletons, balancer
    local UPSTREAMS_FIXTURES
    local TARGETS_FIXTURES
    local upstream_hc
    local upstream_ph

    lazy_teardown(function()
      ngx.log:revert() -- luacheck: ignore
    end)


    lazy_setup(function()
      stub(ngx, "log")

      balancer = require "kong.runloop.balancer"
      singletons = require "kong.singletons"
      singletons.worker_events = require "resty.worker.events"
      singletons.db = {}

      singletons.worker_events.configure({
        shm = "kong_process_events", -- defined by "lua_shared_dict"
        timeout = 5,            -- life time of event data in shm
        interval = 1,           -- poll interval (seconds)

        wait_interval = 0.010,  -- wait before retry fetching event data
        wait_max = 0.5,         -- max wait time before discarding event
      })

      local hc_defaults = {
        active = {
          timeout = 1,
          concurrency = 10,
          http_path = "/",
          healthy = {
            interval = 0,  -- 0 = probing disabled by default
            http_statuses = { 200, 302 },
            successes = 0, -- 0 = disabled by default
          },
          unhealthy = {
            interval = 0, -- 0 = probing disabled by default
            http_statuses = { 429, 404,
                              500, 501, 502, 503, 504, 505 },
            tcp_failures = 0,  -- 0 = disabled by default
            timeouts = 0,      -- 0 = disabled by default
            http_failures = 0, -- 0 = disabled by default
          },
        },
        passive = {
          healthy = {
            http_statuses = { 200, 201, 202, 203, 204, 205, 206, 207, 208, 226,
                              300, 301, 302, 303, 304, 305, 306, 307, 308 },
            successes = 0,
          },
          unhealthy = {
            http_statuses = { 429, 500, 503 },
            tcp_failures = 0,  -- 0 = circuit-breaker disabled by default
            timeouts = 0,      -- 0 = circuit-breaker disabled by default
            http_failures = 0, -- 0 = circuit-breaker disabled by default
          },
        },
      }

      local passive_hc = utils.deep_copy(hc_defaults)
      passive_hc.passive.healthy.successes = 1
      passive_hc.passive.unhealthy.tcp_failures = 1 -- 1 = required because http failures is 1 as well
      passive_hc.passive.unhealthy.http_failures = 1

      UPSTREAMS_FIXTURES = {
        [1] = { id = "a", ws_id = ws_id, name = "mashape", slots = 10, healthchecks = hc_defaults, algorithm = "round-robin" },
        [2] = { id = "b", ws_id = ws_id, name = "kong",    slots = 10, healthchecks = hc_defaults, algorithm = "round-robin" },
        [3] = { id = "c", ws_id = ws_id, name = "gelato",  slots = 20, healthchecks = hc_defaults, algorithm = "round-robin" },
        [4] = { id = "d", ws_id = ws_id, name = "galileo", slots = 20, healthchecks = hc_defaults, algorithm = "round-robin" },
        [5] = { id = "e", ws_id = ws_id, name = "upstream_e", slots = 10, healthchecks = hc_defaults, algorithm = "round-robin" },
        [6] = { id = "f", ws_id = ws_id, name = "upstream_f", slots = 10, healthchecks = hc_defaults, algorithm = "round-robin" },
        [7] = { id = "hc_" .. consistency, ws_id = ws_id, name = "upstream_hc_" .. consistency, slots = 10, healthchecks = passive_hc, algorithm = "round-robin" },
        [8] = { id = "ph", ws_id = ws_id, name = "upstream_ph", slots = 10, healthchecks = passive_hc, algorithm = "round-robin" },
        [9] = { id = "otes", ws_id = ws_id, name = "upstream_otes", slots = 10, healthchecks = hc_defaults, algorithm = "round-robin" },
        [10] = { id = "otee", ws_id = ws_id, name = "upstream_otee", slots = 10, healthchecks = hc_defaults, algorithm = "round-robin" },
      }
      upstream_hc = UPSTREAMS_FIXTURES[7]
      upstream_ph = UPSTREAMS_FIXTURES[8]

      TARGETS_FIXTURES = {
        -- 1st upstream; a
        {
          id = "a1",
          ws_id = ws_id,
          created_at = "003",
          upstream = { id = "a", ws_id = ws_id },
          target = "localhost:80",
          weight = 10,
        },
        {
          id = "a2",
          ws_id = ws_id,
          created_at = "002",
          upstream = { id = "a", ws_id = ws_id },
          target = "localhost:80",
          weight = 10,
        },
        {
          id = "a3",
          ws_id = ws_id,
          created_at = "001",
          upstream = { id = "a", ws_id = ws_id },
          target = "localhost:80",
          weight = 10,
        },
        {
          id = "a4",
          ws_id = ws_id,
          created_at = "002",  -- same timestamp as "a2"
          upstream = { id = "a", ws_id = ws_id },
          target = "localhost:80",
          weight = 10,
        },
        -- 2nd upstream; b
        {
          id = "b1",
          ws_id = ws_id,
          created_at = "003",
          upstream = { id = "b", ws_id = ws_id },
          target = "localhost:80",
          weight = 10,
        },
        -- 3rd upstream: e (removed and re-added)
        {
          id = "e1",
          ws_id = ws_id,
          created_at = "001",
          upstream = { id = "e", ws_id = ws_id },
          target = "127.0.0.1:2112",
          weight = 10,
        },
        {
          id = "e2",
          ws_id = ws_id,
          created_at = "002",
          upstream = { id = "e", ws_id = ws_id },
          target = "127.0.0.1:2112",
          weight = 0,
        },
        {
          id = "e3",
          ws_id = ws_id,
          created_at = "003",
          upstream = { id = "e", ws_id = ws_id },
          target = "127.0.0.1:2112",
          weight = 10,
        },
        -- 4th upstream: f (removed and not re-added)
        {
          id = "f1",
          ws_id = ws_id,
          created_at = "001",
          upstream = { id = "f", ws_id = ws_id },
          target = "127.0.0.1:5150",
          weight = 10,
        },
        {
          id = "f2",
          ws_id = ws_id,
          created_at = "002",
          upstream = { id = "f", ws_id = ws_id },
          target = "127.0.0.1:5150",
          weight = 0,
        },
        {
          id = "f3",
          ws_id = ws_id,
          created_at = "003",
          upstream = { id = "f", ws_id = ws_id },
          target = "127.0.0.1:2112",
          weight = 10,
        },
        -- upstream_hc
        {
          id = "hc1" .. consistency,
          ws_id = ws_id,
          created_at = "001",
          upstream = { id = "hc_" .. consistency, ws_id = ws_id },
          target = "localhost:1111",
          weight = 10,
        },
        -- upstream_ph
        {
          id = "ph1",
          ws_id = ws_id,
          created_at = "001",
          upstream = { id = "ph", ws_id = ws_id },
          target = "localhost:1111",
          weight = 10,
        },
        {
          id = "ph2",
          ws_id = ws_id,
          created_at = "001",
          upstream = { id = "ph", ws_id = ws_id },
          target = "127.0.0.1:2222",
          weight = 10,
        },
        -- upstream_otes
        {
          id = "otes1",
          ws_id = ws_id,
          created_at = "001",
          upstream = { id = "otes", ws_id = ws_id },
          target = "localhost:1111",
          weight = 10,
        },
        -- upstream_otee
        {
          id = "otee1",
          ws_id = ws_id,
          created_at = "001",
          upstream = { id = "otee", ws_id = ws_id },
          target = "localhost:1111",
          weight = 10,
        },
      }

      local function each(fixture)
        return function()
          local i = 0
          return function(self)
            i = i + 1
            return fixture[i]
          end
        end
      end

      local function select(fixture)
        return function(self, pk)
          for item in self:each() do
            if item.id == pk.id then
              return item
            end
          end
        end
      end

      singletons.db = {
        targets = {
          each = each(TARGETS_FIXTURES),
          select_by_upstream_raw = function(self, upstream_pk)
            local upstream_id = upstream_pk.id
            local res, len = {}, 0
            for tgt in self:each() do
              if tgt.upstream.id == upstream_id then
                tgt.order = string.format("%d:%s", tgt.created_at * 1000, tgt.id)
                len = len + 1
                res[len] = tgt
              end
            end

            table.sort(res, function(a, b) return a.order < b.order end)
            return res
          end
        },
        upstreams = {
          each = each(UPSTREAMS_FIXTURES),
          select = select(UPSTREAMS_FIXTURES),
        },
      }

      singletons.core_cache = {
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
        end
      }


    end)

    describe("create_balancer()", function()
      local dns_client = require("resty.dns.client")
      dns_client.init()

      it("creates a balancer with a healthchecker", function()
        setup_it_block(consistency)
        local my_balancer = assert(balancer._create_balancer(UPSTREAMS_FIXTURES[1]))
        local hc = assert(balancer._get_healthchecker(my_balancer))
        hc:stop()
      end)

      it("reuses a balancer by default", function()
        local b1 = assert(balancer._create_balancer(UPSTREAMS_FIXTURES[1]))
        local hc1 = balancer._get_healthchecker(b1)
        local b2 = balancer._create_balancer(UPSTREAMS_FIXTURES[1])
        assert.equal(b1, b2)
        assert(hc1:stop())
      end)

      it("re-creates a balancer if told to", function()
        setup_it_block(consistency)
        balancer.init()
        local b1 = assert(balancer._create_balancer(UPSTREAMS_FIXTURES[1], true))
        local hc1 = balancer._get_healthchecker(b1)
        assert(hc1:stop())
        local b2 = assert(balancer._create_balancer(UPSTREAMS_FIXTURES[1], true))
        local hc2 = balancer._get_healthchecker(b2)
        assert(hc2:stop())
        assert.not_same(b1, b2)
      end)
    end)

    describe("get_balancer()", function()
      local dns_client = require("resty.dns.client")
      dns_client.init()

      it("balancer and healthchecker match; remove and re-add", function()
        setup_it_block(consistency)
        local my_balancer = assert(balancer._get_balancer({
          host = "upstream_e"
        }, true))
        local hc = assert(balancer._get_healthchecker(my_balancer))
        assert.same(1, #hc.targets)
        assert.truthy(hc.targets["127.0.0.1"])
        assert.truthy(hc.targets["127.0.0.1"][2112])
      end)

      it("balancer and healthchecker match; remove and not re-add", function()
        setup_it_block(consistency)
        local my_balancer = assert(balancer._get_balancer({
          host = "upstream_f"
        }, true))
        local hc = assert(balancer._get_healthchecker(my_balancer))
        assert.same(1, #hc.targets)
        assert.truthy(hc.targets["127.0.0.1"])
        assert.truthy(hc.targets["127.0.0.1"][2112])
      end)
    end)

    describe("load_upstreams_dict_into_memory()", function()
      local upstreams_dict
      lazy_setup(function()
        upstreams_dict = balancer._load_upstreams_dict_into_memory()
      end)

      it("retrieves all upstreams as a dictionary", function()
        assert.is.table(upstreams_dict)
        for _, u in ipairs(UPSTREAMS_FIXTURES) do
          assert.equal(upstreams_dict[ws_id .. ":" .. u.name], u.id)
          upstreams_dict[ws_id .. ":" .. u.name] = nil -- remove each match
        end
        assert.is_nil(next(upstreams_dict)) -- should be empty now
      end)
    end)

    describe("get_all_upstreams()", function()
      it("gets a map of all upstream names to ids", function()
        setup_it_block(consistency)
        local upstreams_dict = balancer.get_all_upstreams()

        local fixture_dict = {}
        for _, upstream in ipairs(UPSTREAMS_FIXTURES) do
          fixture_dict[ws_id .. ":" .. upstream.name] = upstream.id
        end

        assert.same(fixture_dict, upstreams_dict)
      end)
    end)

    describe("get_upstream_by_name()", function()
      it("retrieves a complete upstream based on its name", function()
        setup_it_block(consistency)
        for _, fixture in ipairs(UPSTREAMS_FIXTURES) do
          local upstream = balancer.get_upstream_by_name(fixture.name)
          assert.same(fixture, upstream)
        end
      end)
    end)

    describe("load_targets_into_memory()", function()
      local targets
      local upstream

      it("retrieves all targets per upstream, ordered", function()
        setup_it_block(consistency)
        upstream = "a"
        targets = balancer._load_targets_into_memory(upstream)
        assert.equal(4, #targets)
        assert(targets[1].id == "a3")
        assert(targets[2].id == "a2")
        assert(targets[3].id == "a4")
        assert(targets[4].id == "a1")
      end)
    end)

    describe("post_health()", function()
      local hc, my_balancer

      lazy_setup(function()
        my_balancer = assert(balancer._create_balancer(upstream_ph))
        hc = assert(balancer._get_healthchecker(my_balancer))
      end)

      lazy_teardown(function()
        if hc then
          hc:stop()
        end
      end)

      it("posts healthy/unhealthy using IP and hostname", function()
        setup_it_block(consistency)
        local tests = {
          { host = "127.0.0.1", port = 2222, health = true },
          { host = "127.0.0.1", port = 2222, health = false },
          { host = "localhost", port = 1111, health = true },
          { host = "localhost", port = 1111, health = false },
        }
        for _, t in ipairs(tests) do
          assert(balancer.post_health(upstream_ph, t.host, nil, t.port, t.health))
          local health_info = assert(balancer.get_upstream_health("ph"))
          local response = t.health and "HEALTHY" or "UNHEALTHY"
          assert.same(response,
                      health_info[t.host .. ":" .. t.port].addresses[1].health)
        end
      end)

      it("fails if upstream/balancer doesn't exist", function()
        local bad = { name = "invalid", id = "bad" }
        local ok, err = balancer.post_health(bad, "127.0.0.1", 1111, true)
        assert.falsy(ok)
        assert.match(err, "Upstream invalid has no balancer")
      end)
    end)

    describe("healthcheck events", function()
      it("(un)subscribe_to_healthcheck_events()", function()
        setup_it_block(consistency)
        local my_balancer = assert(balancer._create_balancer(upstream_hc))
        local hc = assert(balancer._get_healthchecker(my_balancer))
        local data = {}
        local cb = function(upstream_id, ip, port, hostname, health)
          table.insert(data, {
            upstream_id = upstream_id,
            ip = ip,
            port = port,
            hostname = hostname,
            health = health,
          })
        end
        balancer.subscribe_to_healthcheck_events(cb)
        my_balancer.report_http_status({
          address = {
            ip = "127.0.0.1",
            port = 1111,
            host = {hostname = "localhost"},
          }}, 429)
        my_balancer.report_http_status({
          address = {
            ip = "127.0.0.1",
            port = 1111,
            host = {hostname = "localhost"},
          }}, 200)
        balancer.unsubscribe_from_healthcheck_events(cb)
        my_balancer.report_http_status({
          address = {
            ip = "127.0.0.1",
            port = 1111,
            host = {hostname = "localhost"},
          }}, 429)
        hc:stop()
        assert.same({
          upstream_id = "hc_" .. consistency,
          ip = "127.0.0.1",
          port = 1111,
          hostname = "localhost",
          health = "unhealthy"
        }, data[1])
        assert.same({
          upstream_id = "hc_" .. consistency,
          ip = "127.0.0.1",
          port = 1111,
          hostname = "localhost",
          health = "healthy"
        }, data[2])
        assert.same(nil, data[3])
      end)
    end)

  end)
end
