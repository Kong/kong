describe("Balancer", function()
  local singletons, balancer
  local UPSTREAMS_FIXTURES
  local TARGETS_FIXTURES
  local crc32 = ngx.crc32_short
  local uuid = require("kong.tools.utils").uuid


  teardown(function()
    ngx.log:revert()
  end)


  setup(function()
    stub(ngx, "log")

    balancer = require "kong.core.balancer"
    singletons = require "kong.singletons"
    singletons.worker_events = require "resty.worker.events"
    singletons.dao = {}
    singletons.dao.upstreams = {
      find_all = function(self)
        return UPSTREAMS_FIXTURES
      end
    }

    singletons.worker_events.configure({
      shm = "kong_process_events", -- defined by "lua_shared_dict"
      timeout = 5,            -- life time of event data in shm
      interval = 1,           -- poll interval (seconds)

      wait_interval = 0.010,  -- wait before retry fetching event data
      wait_max = 0.5,         -- max wait time before discarding event
    })

    UPSTREAMS_FIXTURES = {
      {id = "a", name = "mashape", slots = 10, orderlist = {1,2,3,4,5,6,7,8,9,10} },
      {id = "b", name = "kong",    slots = 10, orderlist = {10,9,8,7,6,5,4,3,2,1} },
      {id = "c", name = "gelato",  slots = 20, orderlist = {1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20} },
      {id = "d", name = "galileo", slots = 20, orderlist = {20,19,18,17,16,15,14,13,12,11,10,9,8,7,6,5,4,3,2,1} },
      {id = "e", name = "upstream_e", slots = 10, orderlist = {1,2,3,4,5,6,7,8,9,10} },
      {id = "f", name = "upstream_f", slots = 10, orderlist = {1,2,3,4,5,6,7,8,9,10} },
    }

    singletons.dao.targets = {
      find_all = function(self, match_on)
        local ret = {}
        for _, rec in ipairs(TARGETS_FIXTURES) do
          for key, val in pairs(match_on or {}) do
            if rec[key] ~= val then
              rec = nil
              break
            end
          end
          if rec then table.insert(ret, rec) end
        end
        return ret
      end
    }

    TARGETS_FIXTURES = {
      -- 1st upstream; a
      {
        id = "a1",
        created_at = "003",
        upstream_id = "a",
        target = "mashape.com:80",
        weight = 10,
      },
      {
        id = "a2",
        created_at = "002",
        upstream_id = "a",
        target = "mashape.com:80",
        weight = 10,
      },
      {
        id = "a3",
        created_at = "001",
        upstream_id = "a",
        target = "mashape.com:80",
        weight = 10,
      },
      {
        id = "a4",
        created_at = "002",  -- same timestamp as "a2"
        upstream_id = "a",
        target = "mashape.com:80",
        weight = 10,
      },
      -- 2nd upstream; b
      {
        id = "b1",
        created_at = "003",
        upstream_id = "b",
        target = "mashape.com:80",
        weight = 10,
      },
      -- 3rd upstream: e (removed and re-added)
      {
        id = "e1",
        created_at = "001",
        upstream_id = "e",
        target = "127.0.0.1:2112",
        weight = 10,
      },
      {
        id = "e2",
        created_at = "002",
        upstream_id = "e",
        target = "127.0.0.1:2112",
        weight = 0,
      },
      {
        id = "e3",
        created_at = "003",
        upstream_id = "e",
        target = "127.0.0.1:2112",
        weight = 10,
      },
      -- 4th upstream: f (removed and not re-added)
      {
        id = "f1",
        created_at = "001",
        upstream_id = "f",
        target = "127.0.0.1:5150",
        weight = 10,
      },
      {
        id = "f2",
        created_at = "002",
        upstream_id = "f",
        target = "127.0.0.1:5150",
        weight = 0,
      },
      {
        id = "f3",
        created_at = "003",
        upstream_id = "f",
        target = "127.0.0.1:2112",
        weight = 10,
      },
    }

    local function find_all_in_fixture_fn(fixture)
      return function(self, match_on)
        local ret = {}
        for _, rec in ipairs(fixture) do
          for key, val in pairs(match_on or {}) do
            if rec[key] ~= val then
              rec = nil
              break
            end
          end
          if rec then table.insert(ret, rec) end
        end
        return ret
      end
    end

    singletons.dao = {
      targets = {
        find_all = find_all_in_fixture_fn(TARGETS_FIXTURES)
      },
      upstreams = {
        find_all = find_all_in_fixture_fn(UPSTREAMS_FIXTURES)
      },
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
      local my_balancer = balancer._create_balancer(UPSTREAMS_FIXTURES[1])
      assert.truthy(my_balancer)
      local hc = balancer._get_healthchecker(my_balancer)
      local target_history = {
        { name = "mashape.com", port = 80, order = "001:a3", weight = 10 },
        { name = "mashape.com", port = 80, order = "002:a2", weight = 10 },
        { name = "mashape.com", port = 80, order = "002:a4", weight = 10 },
        { name = "mashape.com", port = 80, order = "003:a1", weight = 10 },
      }
      assert.same(target_history, balancer._get_target_history(my_balancer))
      assert.truthy(hc)
      hc:stop()
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
      local my_balancer = balancer._get_balancer({ host = "upstream_e" }, true)
      assert.truthy(my_balancer)
      local target_history = {
        { name = "127.0.0.1", port = 2112, order = "001:e1", weight = 10 },
        { name = "127.0.0.1", port = 2112, order = "002:e2", weight = 0  },
        { name = "127.0.0.1", port = 2112, order = "003:e3", weight = 10 },
      }
      assert.same(target_history, balancer._get_target_history(my_balancer))
      local hc = balancer._get_healthchecker(my_balancer)
      assert.truthy(hc)
      assert.same(1, #hc.targets)
      assert.truthy(hc.targets["127.0.0.1"])
      assert.truthy(hc.targets["127.0.0.1"][2112])
    end)

    it("balancer and healthchecker match; remove and not re-add", function()
      local my_balancer = balancer._get_balancer({ host = "upstream_f" }, true)
      assert.truthy(my_balancer)
      local target_history = {
        { name = "127.0.0.1", port = 5150, order = "001:f1", weight = 10 },
        { name = "127.0.0.1", port = 5150, order = "002:f2", weight = 0  },
        { name = "127.0.0.1", port = 2112, order = "003:f3", weight = 10 },
      }
      assert.same(target_history, balancer._get_target_history(my_balancer))
      local hc = balancer._get_healthchecker(my_balancer)
      assert.truthy(hc)
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
