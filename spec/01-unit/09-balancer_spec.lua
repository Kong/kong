local utils = require "kong.tools.utils"

describe("Balancer", function()
  local singletons, balancer
  local UPSTREAMS_FIXTURES
  local TARGETS_FIXTURES
  local crc32 = ngx.crc32_short
  local uuid = require("kong.tools.utils").uuid
  local upstream_hc
  local upstream_ph
  local upstream_ote

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
    passive_hc.passive.unhealthy.http_failures = 1

    UPSTREAMS_FIXTURES = {
      [1] = { id = "a", name = "mashape", slots = 10, healthchecks = hc_defaults, algorithm = "round-robin" },
      [2] = { id = "b", name = "kong",    slots = 10, healthchecks = hc_defaults, algorithm = "round-robin" },
      [3] = { id = "c", name = "gelato",  slots = 20, healthchecks = hc_defaults, algorithm = "round-robin" },
      [4] = { id = "d", name = "galileo", slots = 20, healthchecks = hc_defaults, algorithm = "round-robin" },
      [5] = { id = "e", name = "upstream_e", slots = 10, healthchecks = hc_defaults, algorithm = "round-robin" },
      [6] = { id = "f", name = "upstream_f", slots = 10, healthchecks = hc_defaults, algorithm = "round-robin" },
      [7] = { id = "hc", name = "upstream_hc", slots = 10, healthchecks = passive_hc, algorithm = "round-robin" },
      [8] = { id = "ph", name = "upstream_ph", slots = 10, healthchecks = passive_hc, algorithm = "round-robin" },
      [9] = { id = "ote", name = "upstream_ote", slots = 10, healthchecks = hc_defaults, algorithm = "round-robin" },
    }
    upstream_hc = UPSTREAMS_FIXTURES[7]
    upstream_ph = UPSTREAMS_FIXTURES[8]
    upstream_ote = UPSTREAMS_FIXTURES[9]

    TARGETS_FIXTURES = {
      -- 1st upstream; a
      {
        id = "a1",
        created_at = "003",
        upstream = { id = "a" },
        target = "localhost:80",
        weight = 10,
      },
      {
        id = "a2",
        created_at = "002",
        upstream = { id = "a" },
        target = "localhost:80",
        weight = 10,
      },
      {
        id = "a3",
        created_at = "001",
        upstream = { id = "a" },
        target = "localhost:80",
        weight = 10,
      },
      {
        id = "a4",
        created_at = "002",  -- same timestamp as "a2"
        upstream = { id = "a" },
        target = "localhost:80",
        weight = 10,
      },
      -- 2nd upstream; b
      {
        id = "b1",
        created_at = "003",
        upstream = { id = "b" },
        target = "localhost:80",
        weight = 10,
      },
      -- 3rd upstream: e (removed and re-added)
      {
        id = "e1",
        created_at = "001",
        upstream = { id = "e" },
        target = "127.0.0.1:2112",
        weight = 10,
      },
      {
        id = "e2",
        created_at = "002",
        upstream = { id = "e" },
        target = "127.0.0.1:2112",
        weight = 0,
      },
      {
        id = "e3",
        created_at = "003",
        upstream = { id = "e" },
        target = "127.0.0.1:2112",
        weight = 10,
      },
      -- 4th upstream: f (removed and not re-added)
      {
        id = "f1",
        created_at = "001",
        upstream = { id = "f" },
        target = "127.0.0.1:5150",
        weight = 10,
      },
      {
        id = "f2",
        created_at = "002",
        upstream = { id = "f" },
        target = "127.0.0.1:5150",
        weight = 0,
      },
      {
        id = "f3",
        created_at = "003",
        upstream = { id = "f" },
        target = "127.0.0.1:2112",
        weight = 10,
      },
      -- upstream_hc
      {
        id = "hc1",
        created_at = "001",
        upstream = { id = "hc" },
        target = "localhost:1111",
        weight = 10,
      },
      -- upstream_ph
      {
        id = "ph1",
        created_at = "001",
        upstream = { id = "ph" },
        target = "localhost:1111",
        weight = 10,
      },
      {
        id = "ph2",
        created_at = "001",
        upstream = { id = "ph" },
        target = "127.0.0.1:2222",
        weight = 10,
      },
      -- upstream_ote
      {
        id = "ote1",
        created_at = "001",
        upstream = { id = "ote" },
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
      local my_balancer = assert(balancer._create_balancer(UPSTREAMS_FIXTURES[1]))
      local hc = assert(balancer._get_healthchecker(my_balancer))
      local target_history = {
        { name = "localhost", port = 80, order = "1000:a3", weight = 10 },
        { name = "localhost", port = 80, order = "2000:a2", weight = 10 },
        { name = "localhost", port = 80, order = "2000:a4", weight = 10 },
        { name = "localhost", port = 80, order = "3000:a1", weight = 10 },
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
      local b1_target_history = balancer._get_target_history(b1)
      local b2 = assert(balancer._create_balancer(UPSTREAMS_FIXTURES[1], true))
      local hc2 = balancer._get_healthchecker(b2)
      assert(hc2:stop())
      local target_history = {
        { name = "localhost", port = 80, order = "1000:a3", weight = 10 },
        { name = "localhost", port = 80, order = "2000:a2", weight = 10 },
        { name = "localhost", port = 80, order = "2000:a4", weight = 10 },
        { name = "localhost", port = 80, order = "3000:a1", weight = 10 },
      }
      assert.not_same(b1, b2)
      assert.same(target_history, b1_target_history)
      assert.same(target_history, balancer._get_target_history(b2))
    end)
  end)

  describe("get_balancer()", function()
    local dns_client = require("resty.dns.client")
    dns_client.init()

    lazy_setup(function()
      -- In these tests, we pass `true` to get_balancer
      -- to ensure that the upstream was created by `balancer.init()`
      balancer.init()
    end)

    it("balancer and healthchecker match; remove and re-add", function()
      local my_balancer = assert(balancer._get_balancer({
        host = "upstream_e"
      }, true))
      local target_history = {
        { name = "127.0.0.1", port = 2112, order = "1000:e1", weight = 10 },
        { name = "127.0.0.1", port = 2112, order = "2000:e2", weight = 0  },
        { name = "127.0.0.1", port = 2112, order = "3000:e3", weight = 10 },
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
        { name = "127.0.0.1", port = 5150, order = "1000:f1", weight = 10 },
        { name = "127.0.0.1", port = 5150, order = "2000:f2", weight = 0  },
        { name = "127.0.0.1", port = 2112, order = "3000:f3", weight = 10 },
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
    lazy_setup(function()
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
    lazy_setup(function()
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
    lazy_setup(function()
      balancer._load_targets_into_memory("ote")
    end)

    it("adding a target does not recreate a balancer", function()
      local b1 = balancer._create_balancer(upstream_ote)
      assert.same(1, #(balancer._get_target_history(b1)))

      table.insert(TARGETS_FIXTURES, {
        id = "ote2",
        created_at = "002",
        upstream = { id = "ote" },
        target = "localhost:1112",
        weight = 10,
      })
      balancer.on_target_event("create", { upstream = { id = "ote" } })

      local b2 = balancer._create_balancer(upstream_ote)
      assert.same(2, #(balancer._get_target_history(b2)))

      assert(b1 == b2)
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

    it("requires hostname if that was used in the Target", function()
      local ok = balancer.post_health(upstream_ph, "127.0.0.1", nil, 1111, true)
      assert.truthy(ok) -- healthchecker does not report error...
      local health_info = assert(balancer.get_upstream_health("ph"))
      -- ...but health does not update
      assert.same("UNHEALTHY", health_info["localhost:1111"].addresses[1].health)

      ok = balancer.post_health(upstream_ph, "localhost", nil, 1111, true)
      assert.truthy(ok) -- healthcheck returns true...
      health_info = assert(balancer.get_upstream_health("ph"))
      -- ...and health updates
      assert.same("HEALTHY", health_info["localhost:1111"].addresses[1].health)
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
    describe("cookie", function()
      it("uses the cookie when present in the request", function()
        local value = "some cookie value"
        ngx.var.cookie_Foo = value
        ngx.ctx.balancer_data = {}
        local hash = balancer._create_hash({
          hash_on = "cookie",
          hash_on_cookie = "Foo",
        })
        assert.are.same(crc32(value), hash)
        assert.is_nil(ngx.ctx.balancer_data.hash_cookie)
      end)
      it("creates the cookie when not present in the request", function()
        ngx.ctx.balancer_data = {}
        balancer._create_hash({
          hash_on = "cookie",
          hash_on_cookie = "Foo",
          hash_on_cookie_path = "/",
        })
        assert.are.same(ngx.ctx.balancer_data.hash_cookie.key, "Foo")
        assert.are.same(ngx.ctx.balancer_data.hash_cookie.path, "/")
      end)
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
      describe("cookie", function()
        it("uses the cookie when present in the request", function()
          local value = "some cookie value"
          ngx.var.cookie_Foo = value
          ngx.ctx.balancer_data = {}
          local hash = balancer._create_hash({
            hash_on = "consumer",
            hash_fallback = "cookie",
            hash_on_cookie = "Foo",
          })
          assert.are.same(crc32(value), hash)
          assert.is_nil(ngx.ctx.balancer_data.hash_cookie)
        end)
        it("creates the cookie when not present in the request", function()
          ngx.ctx.balancer_data = {}
          balancer._create_hash({
            hash_on = "consumer",
            hash_fallback = "cookie",
            hash_on_cookie = "Foo",
            hash_on_cookie_path = "/",
          })
          assert.are.same(ngx.ctx.balancer_data.hash_cookie.key, "Foo")
          assert.are.same(ngx.ctx.balancer_data.hash_cookie.path, "/")
        end)
      end)
    end)
  end)

end)
