local utils = require "kong.tools.utils"

describe("Balancer", function()
  local singletons, balancer
  local WORKSPACE_FIXTURES
  local UPSTREAMS_FIXTURES
  local TARGETS_FIXTURES
  local crc32 = ngx.crc32_short
  local uuid = require("kong.tools.utils").uuid
  local upstream_hc
  local upstream_ph
  local upstream_ote

  teardown(function()
    ngx.log:revert()
  end)


  setup(function()
    stub(ngx, "log")

    balancer = require "kong.core.balancer"
    singletons = require "kong.singletons"
    singletons.worker_events = require "resty.worker.events"
    singletons.dao = {}

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
    passive_hc.passive.unhealthy.http_failures = 1

    WORKSPACE_FIXTURES = { {id = "1", name = "default"}}
    UPSTREAMS_FIXTURES = {
      [1] = { id = "a", name = "mashape", slots = 10, healthchecks = hc_defaults, ws_id = "1"},
      [2] = { id = "b", name = "kong",    slots = 10, healthchecks = hc_defaults, ws_id = "1"},
      [3] = { id = "c", name = "gelato",  slots = 20, healthchecks = hc_defaults, ws_id = "1"},
      [4] = { id = "d", name = "galileo", slots = 20, healthchecks = hc_defaults, ws_id = "1"},
      [5] = { id = "e", name = "upstream_e", slots = 10, healthchecks = hc_defaults, ws_id = "1"},
      [6] = { id = "f", name = "upstream_f", slots = 10, healthchecks = hc_defaults, ws_id = "1"},
      [7] = { id = "hc", name = "upstream_hc", slots = 10, healthchecks = passive_hc, ws_id = "1"},
      [8] = { id = "ph", name = "upstream_ph", slots = 10, healthchecks = passive_hc, ws_id = "1"},
      [9] = { id = "ote", name = "upstream_ote", slots = 10, healthchecks = hc_defaults, ws_id = "1"},
    }
    upstream_hc = UPSTREAMS_FIXTURES[7]
    upstream_ph = UPSTREAMS_FIXTURES[8]
    upstream_ote = UPSTREAMS_FIXTURES[9]

    TARGETS_FIXTURES = {
      -- 1st upstream; a
      {
        id = "a1",
        created_at = "003",
        upstream_id = "a",
        target = "mashape.com:80",
        weight = 10,
        ws_id = "1",
      },
      {
        id = "a2",
        created_at = "002",
        upstream_id = "a",
        target = "mashape.com:80",
        weight = 10,
        ws_id = "1",
      },
      {
        id = "a3",
        created_at = "001",
        upstream_id = "a",
        target = "mashape.com:80",
        weight = 10,
        ws_id = "1",
      },
      {
        id = "a4",
        created_at = "002",  -- same timestamp as "a2"
        upstream_id = "a",
        target = "mashape.com:80",
        weight = 10,
        ws_id = "1",
      },
      -- 2nd upstream; b
      {
        id = "b1",
        created_at = "003",
        upstream_id = "b",
        target = "mashape.com:80",
        weight = 10,
        ws_id = "1",
      },
      -- 3rd upstream: e (removed and re-added)
      {
        id = "e1",
        created_at = "001",
        upstream_id = "e",
        target = "127.0.0.1:2112",
        weight = 10,
        ws_id = "1",
      },
      {
        id = "e2",
        created_at = "002",
        upstream_id = "e",
        target = "127.0.0.1:2112",
        weight = 0,
        ws_id = "1",
      },
      {
        id = "e3",
        created_at = "003",
        upstream_id = "e",
        target = "127.0.0.1:2112",
        weight = 10,
        ws_id = "1",
      },
      -- 4th upstream: f (removed and not re-added)
      {
        id = "f1",
        created_at = "001",
        upstream_id = "f",
        target = "127.0.0.1:5150",
        weight = 10,
        ws_id = "1",
      },
      {
        id = "f2",
        created_at = "002",
        upstream_id = "f",
        target = "127.0.0.1:5150",
        weight = 0,
        ws_id = "1",
      },
      {
        id = "f3",
        created_at = "003",
        upstream_id = "f",
        target = "127.0.0.1:2112",
        weight = 10,
        ws_id = "1",
      },
      -- upstream_hc
      {
        id = "hc1",
        created_at = "001",
        upstream_id = "hc",
        target = "localhost:1111",
        weight = 10,
        ws_id = "1",
      },
      -- upstream_ph
      {
        id = "ph1",
        created_at = "001",
        upstream_id = "ph",
        target = "localhost:1111",
        weight = 10,
        ws_id = "1",
      },
      {
        id = "ph2",
        created_at = "001",
        upstream_id = "ph",
        target = "127.0.0.1:2222",
        weight = 10,
        ws_id = "1",
      },
      -- upstream_ote
      {
        id = "ote1",
        created_at = "001",
        upstream_id = "ote",
        target = "localhost:1111",
        weight = 10,
        ws_id = "1",
      },
    }

    local function find_all_in_fixture_fn(fixture)
      local function in_ws(ws_id, wss)
        for _, v in ipairs(wss) do
          if v.id == ws_id then
            return true
          end
        end
      end

      return function(self, match_on)

        local ret = {}
        for _, rec in ipairs(fixture) do
          for key, val in pairs(match_on or {}) do
            if rec[key] ~= val then
              rec = nil
              break
            end
            if ngx.ctx.workspaces ~= nil and #ngx.ctx.workspaces ~= 0 then
              if not in_ws(rec.ws_id, ngx.ctx.workspaces) then
                rec = nil
                break
              end
            end
          end
          if rec then table.insert(ret, rec) end
        end
        return ret
      end
    end

    local function _run_with_ws_scope(self, ws_scope, cb, ...)
      local old_ws = ngx.ctx.workspaces
      ngx.ctx.workspaces = ws_scope
      local res, err = cb(self, ...)
      ngx.ctx.workspaces = old_ws
      return res, err
    end

    singletons.dao = {
      targets = {
        find_all = find_all_in_fixture_fn(TARGETS_FIXTURES)
      },
      upstreams = {
        find_all = find_all_in_fixture_fn(UPSTREAMS_FIXTURES),
        run_with_ws_scope = _run_with_ws_scope
      },
      workspaces = {
        find_all = function() return WORKSPACE_FIXTURES end
      }
    }

    singletons.cache = {
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
      local my_balancer = assert(balancer._create_balancer(UPSTREAMS_FIXTURES[1]))
      local hc = assert(balancer._get_healthchecker(my_balancer))
      local target_history = {
        { name = "mashape.com", port = 80, order = "001:a3", weight = 10 },
        { name = "mashape.com", port = 80, order = "002:a2", weight = 10 },
        { name = "mashape.com", port = 80, order = "002:a4", weight = 10 },
        { name = "mashape.com", port = 80, order = "003:a1", weight = 10 },
      }
      assert.same(target_history, balancer._get_target_history(my_balancer))
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
      local b1 = assert(balancer._create_balancer(UPSTREAMS_FIXTURES[1], true))
      local hc1 = balancer._get_healthchecker(b1)
      assert(hc1:stop())
      local b2 = assert(balancer._create_balancer(UPSTREAMS_FIXTURES[1], true))
      local hc2 = balancer._get_healthchecker(b2)
      assert(hc2:stop())
      local target_history = {
        { name = "mashape.com", port = 80, order = "001:a3", weight = 10 },
        { name = "mashape.com", port = 80, order = "002:a2", weight = 10 },
        { name = "mashape.com", port = 80, order = "002:a4", weight = 10 },
        { name = "mashape.com", port = 80, order = "003:a1", weight = 10 },
      }
      assert.not_same(b1, b2)
      assert.same(target_history, balancer._get_target_history(b1))
      assert.same(target_history, balancer._get_target_history(b2))
    end)
  end)

  describe("get_balancer()", function()
    local dns_client = require("resty.dns.client")
    dns_client.init()

    setup(function()
      -- In these tests, we pass `true` to get_balancer
      -- to ensure that the upstream was created by `balancer.init()`
      balancer.init()
    end)

    it("balancer and healthchecker match; remove and re-add", function()
      ngx.ctx.workspaces = {WORKSPACE_FIXTURES[1]}

      local my_balancer = assert(balancer._get_balancer({
        host = "upstream_e"
      }, true))
      local target_history = {
        { name = "127.0.0.1", port = 2112, order = "001:e1", weight = 10 },
        { name = "127.0.0.1", port = 2112, order = "002:e2", weight = 0  },
        { name = "127.0.0.1", port = 2112, order = "003:e3", weight = 10 },
      }
      assert.same(target_history, balancer._get_target_history(my_balancer))
      local hc = assert(balancer._get_healthchecker(my_balancer))
      assert.same(1, #hc.targets)
      assert.truthy(hc.targets["127.0.0.1"])
      assert.truthy(hc.targets["127.0.0.1"][2112])
    end)

    it("balancer and healthchecker match; remove and not re-add", function()
      local my_balancer = assert(balancer._get_balancer({
        host = "upstream_f"
      }, true))
      local target_history = {
        { name = "127.0.0.1", port = 5150, order = "001:f1", weight = 10 },
        { name = "127.0.0.1", port = 5150, order = "002:f2", weight = 0  },
        { name = "127.0.0.1", port = 2112, order = "003:f3", weight = 10 },
      }
      assert.same(target_history, balancer._get_target_history(my_balancer))
      local hc = assert(balancer._get_healthchecker(my_balancer))
      assert.same(1, #hc.targets)
      assert.truthy(hc.targets["127.0.0.1"])
      assert.truthy(hc.targets["127.0.0.1"][2112])
    end)
  end)

  describe("load_upstreams_dict_into_memory()", function()
    local upstreams_dict
    setup(function()
      upstreams_dict = balancer._load_upstreams_dict_into_memory()
    end)

    it("retrieves all upstreams as a dictionary", function()
      assert.is.table(upstreams_dict)
      for _, u in ipairs(UPSTREAMS_FIXTURES) do
        assert.equal(upstreams_dict[u.name], u.id)
        upstreams_dict[u.name] = nil -- remove each match
      end
      assert.is_nil(next(upstreams_dict)) -- should be empty now
    end)
  end)

  describe("get_all_upstreams()", function()
    it("gets a map of all upstream names to ids", function()
      local upstreams_dict = balancer.get_all_upstreams()

      local fixture_dict = {}
      for _, upstream in ipairs(UPSTREAMS_FIXTURES) do
        fixture_dict[upstream.name] = upstream.id
      end

      assert.same(fixture_dict, upstreams_dict)
    end)
  end)

  describe("get_upstream_by_name()", function()
    it("retrieves a complete upstream based on its name", function()
      for _, fixture in ipairs(UPSTREAMS_FIXTURES) do
        local upstream = balancer.get_upstream_by_name(fixture.name)
        assert.same(fixture, upstream)
      end
    end)
  end)

  describe("load_targets_into_memory()", function()
    local targets
    local upstream
    setup(function()
      upstream = "a"
      targets = balancer._load_targets_into_memory(upstream)
    end)

    it("retrieves all targets per upstream, ordered", function()
      assert.equal(4, #targets)
      assert(targets[1].id == "a3")
      assert(targets[2].id == "a2")
      assert(targets[3].id == "a4")
      assert(targets[4].id == "a1")
    end)
  end)

  describe("on_target_event()", function()
    setup(function()
      balancer._load_targets_into_memory("ote")
    end)

    it("adding a target does not recreate a balancer", function()
      local b1 = balancer._create_balancer(upstream_ote)
      assert.same(1, #(balancer._get_target_history(b1)))

      table.insert(TARGETS_FIXTURES, {
        id = "ote2",
        created_at = "002",
        upstream_id = "ote",
        target = "localhost:1112",
        weight = 10,
        ws_id = "1"
      })
      balancer.on_target_event("create", { upstream_id = "ote" })

      local b2 = balancer._create_balancer(upstream_ote)
      assert.same(2, #(balancer._get_target_history(b2)))

      assert(b1 == b2)
    end)
  end)

  describe("post_health()", function()
    local hc, my_balancer

    setup(function()
      my_balancer = assert(balancer._create_balancer(upstream_ph))
      hc = assert(balancer._get_healthchecker(my_balancer))
    end)

    teardown(function()
      if hc then
        hc:stop()
      end
    end)

    it("posts healthy/unhealthy using IP and hostname", function()
      local tests = {
        { host = "127.0.0.1", port = 2222, health = true },
        { host = "127.0.0.1", port = 2222, health = false },
        { host = "localhost", port = 1111, health = true },
        { host = "localhost", port = 1111, health = false },
      }
      for _, t in ipairs(tests) do
        assert(balancer.post_health(upstream_ph, t.host, t.port, t.health))
        local health_info = assert(balancer.get_upstream_health("ph"))
        local response = t.health and "HEALTHY" or "UNHEALTHY"
        assert.same(response, health_info[t.host .. ":" .. t.port])
      end
    end)

    it("requires hostname if that was used in the Target", function()
      local ok, err = balancer.post_health(upstream_ph, "127.0.0.1", 1111, true)
      assert.falsy(ok)
      assert.match(err, "target not found for 127.0.0.1:1111")
    end)

    it("fails if upstream/balancer doesn't exist", function()
      local bad = { name = "invalid", id = "bad" }
      local ok, err = balancer.post_health(bad, "127.0.0.1", 1111, true)
      assert.falsy(ok)
      assert.match(err, "Upstream invalid has no balancer")
    end)
  end)

  describe("(un)subscribe_to_healthcheck_events()", function()
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
    my_balancer.report_http_status("127.0.0.1", 1111, 429)
    my_balancer.report_http_status("127.0.0.1", 1111, 200)
    balancer.unsubscribe_from_healthcheck_events(cb)
    my_balancer.report_http_status("127.0.0.1", 1111, 429)
    hc:stop()
    assert.same({
      upstream_id = "hc",
      ip = "127.0.0.1",
      port = 1111,
      hostname = "localhost",
      health = "unhealthy"
    }, data[1])
    assert.same({
      upstream_id = "hc",
      ip = "127.0.0.1",
      port = 1111,
      hostname = "localhost",
      health = "healthy"
    }, data[2])
    assert.same(nil, data[3])
  end)

  describe("creating hash values", function()
    local headers
    local backup
    before_each(function()
      headers = setmetatable({}, {
          __newindex = function(self, key, value)
            rawset(self, key:upper(), value)
          end,
          __index = function(self, key)
            return rawget(self, key:upper())
          end,
      })
      backup = { ngx.req, ngx.var, ngx.ctx }
      ngx.req = { get_headers = function() return headers end } -- luacheck: ignore
      ngx.var = {}
      ngx.ctx = {}
    end)
    after_each(function()
      ngx.req = backup[1] -- luacheck: ignore
      ngx.var = backup[2]
      ngx.ctx = backup[3]
    end)
    it("none", function()
      local hash = balancer._create_hash({
          hash_on = "none",
      })
      assert.is_nil(hash)
    end)
    it("consumer", function()
      local value = uuid()
      ngx.ctx.authenticated_consumer = { id = value }
      local hash = balancer._create_hash({
          hash_on = "consumer",
      })
      assert.are.same(crc32(value), hash)
    end)
    it("ip", function()
      local value = "1.2.3.4"
      ngx.var.remote_addr = value
      local hash = balancer._create_hash({
          hash_on = "ip",
      })
      assert.are.same(crc32(value), hash)
    end)
    it("header", function()
      local value = "some header value"
      headers.HeaderName = value
      local hash = balancer._create_hash({
          hash_on = "header",
          hash_on_header = "HeaderName",
      })
      assert.are.same(crc32(value), hash)
    end)
    it("multi-header", function()
      local value = { "some header value", "another value" }
      headers.HeaderName = value
      local hash = balancer._create_hash({
          hash_on = "header",
          hash_on_header = "HeaderName",
      })
      assert.are.same(crc32(table.concat(value)), hash)
    end)
    describe("fallback", function()
      it("none", function()
        local hash = balancer._create_hash({
            hash_on = "consumer",
            hash_fallback = "none",
        })
        assert.is_nil(hash)
      end)
      it("consumer", function()
        local value = uuid()
        ngx.ctx.authenticated_consumer = { id = value }
        local hash = balancer._create_hash({
            hash_on = "header",
            hash_on_header = "non-existing",
            hash_fallback = "consumer",
        })
        assert.are.same(crc32(value), hash)
      end)
      it("ip", function()
        local value = "1.2.3.4"
        ngx.var.remote_addr = value
        local hash = balancer._create_hash({
            hash_on = "consumer",
            hash_fallback = "ip",
        })
        assert.are.same(crc32(value), hash)
      end)
      it("header", function()
        local value = "some header value"
        headers.HeaderName = value
        local hash = balancer._create_hash({
            hash_on = "consumer",
            hash_fallback = "header",
            hash_fallback_header = "HeaderName",
        })
        assert.are.same(crc32(value), hash)
      end)
      it("multi-header", function()
        local value = { "some header value", "another value" }
        headers.HeaderName = value
        local hash = balancer._create_hash({
            hash_on = "consumer",
            hash_fallback = "header",
            hash_fallback_header = "HeaderName",
        })
        assert.are.same(crc32(table.concat(value)), hash)
      end)
    end)
  end)

end)
