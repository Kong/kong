
local client -- forward declaration
local dns_utils = require "kong.resty.dns.utils"
local helpers = require "spec.helpers.dns"
local dnsSRV = function(...) return helpers.dnsSRV(client, ...) end
local dnsA = function(...) return helpers.dnsA(client, ...) end
local dnsExpire = helpers.dnsExpire

local mocker = require "spec.fixtures.mocker"
local utils = require "kong.tools.utils"

local ws_id = utils.uuid()

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

local unset_register = {}
local function setup_block()
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

  local cache_table = {}
  local function register_unsettter(f)
    table.insert(unset_register, f)
  end

  mocker.setup(register_unsettter, {
    kong = {
      configuration = {
        --worker_consistency = consistency,
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

local function unsetup_block()
  for _, f in ipairs(unset_register) do
    f()
  end
end


local balancers, targets

local upstream_index = 0

local function new_balancer(algorithm)
  upstream_index = upstream_index + 1
  local upname="upstream_" .. upstream_index
  local my_upstream = { id=upname, name=upname, ws_id=ws_id, slots=10, healthchecks=hc_defaults, algorithm=algorithm }
  local b = (balancers.create_balancer(my_upstream, true))

  return b
end

local function add_target(b, name, port, weight)

  -- adding again changes weight
  for _, prev_target in ipairs(b.targets) do
    if prev_target.name == name and prev_target.port == port then
      local entry = {port = port}
      for _, addr in ipairs(prev_target.addresses) do
        entry.address = addr.ip
        b:changeWeight(prev_target, entry, weight)
      end
      prev_target.weight = weight
      return prev_target
    end
  end

  -- add new
  local upname = b.upstream and b.upstream.name or b.upstream_id
  local target = {
    upstream = name or upname,
    balancer = b,
    name = name,
    nameType = dns_utils.hostnameType(name),
    addresses = {},
    port = port or 8000,
    weight = weight or 100,
    totalWeight = 0,
    unavailableWeight = 0,
  }

  table.insert(b.targets, target)
  targets.resolve_targets(b.targets)

  return target
end


for _, algorithm in ipairs{ "consistent-hashing", "least-connections", "round-robin" } do

  describe("[" .. algorithm .. "]", function()

    local snapshot

    setup(function()
      _G.package.loaded["kong.resty.dns.client"] = nil -- make sure module is reloaded
      _G.package.loaded["kong.runloop.balancer.targets"] = nil -- make sure module is reloaded

      local kong = {}

      _G.kong = kong

      kong.db = {}

      client = require "kong.resty.dns.client"
      targets = require "kong.runloop.balancer.targets"
      balancers = require "kong.runloop.balancer.balancers"
      local healthcheckers = require "kong.runloop.balancer.healthcheckers"
      healthcheckers.init()
      balancers.init()

      local function empty_each()
        return function() end
      end

      kong.db = {
        targets = {
          each = empty_each,
          select_by_upstream_raw = function()
            return {}
          end
        },
        upstreams = {
          each = empty_each,
          select = function() end,
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
        end
      }

    end)


    before_each(function()
      setup_block()
      assert(client.init {
        hosts = {},
        -- don't supply resolvConf and fallback to default resolver
        -- so that CI and docker can have reliable results
        -- but remove `search` and `domain`
        search = {},
      })
      snapshot = assert:snapshot()
      assert:set_parameter("TableFormatLevel", 10)
    end)


    after_each(function()
      snapshot:revert()  -- undo any spying/stubbing etc.
      unsetup_block()
      collectgarbage()
      collectgarbage()
    end)


    describe("health:", function()

      local b

      before_each(function()
        b = new_balancer(algorithm)
        b.healthThreshold = 50
      end)

      after_each(function()
        b = nil
      end)

      it("empty balancer is unhealthy", function()
        assert.is_false((b:getStatus().healthy))
      end)

      it("adding first address marks healthy", function()
        assert.is_false(b:getStatus().healthy)
        add_target(b, "127.0.0.1", 8000, 100)
        assert.is_true(b:getStatus().healthy)
      end)

      it("dropping below the health threshold marks unhealthy", function()
        assert.is_false(b:getStatus().healthy)
        add_target(b, "127.0.0.1", 8000, 100)
        add_target(b, "127.0.0.2", 8000, 100)
        add_target(b, "127.0.0.3", 8000, 100)
        assert.is_true(b:getStatus().healthy)
        b:setAddressStatus(b:findAddress("127.0.0.2", 8000, "127.0.0.2"), false)
        assert.is_true(b:getStatus().healthy)
        b:setAddressStatus(b:findAddress("127.0.0.3", 8000, "127.0.0.3"), false)
        assert.is_false(b:getStatus().healthy)
      end)

      it("rising above the health threshold marks healthy", function()
        assert.is_false(b:getStatus().healthy)
        add_target(b, "127.0.0.1", 8000, 100)
        add_target(b, "127.0.0.2", 8000, 100)
        add_target(b, "127.0.0.3", 8000, 100)
        b:setAddressStatus(b:findAddress("127.0.0.2", 8000, "127.0.0.2"), false)
        b:setAddressStatus(b:findAddress("127.0.0.3", 8000, "127.0.0.3"), false)
        assert.is_false(b:getStatus().healthy)
        b:setAddressStatus(b:findAddress("127.0.0.2", 8000, "127.0.0.2"), true)
        assert.is_true(b:getStatus().healthy)
      end)

    end)



    describe("weights:", function()

      local b

      before_each(function()
        b = new_balancer(algorithm)
        add_target(b, "127.0.0.1", 8000, 100)  -- add 1 initial host
      end)

      after_each(function()
        b = nil
      end)



      describe("(A)", function()

        it("adding a host",function()
          dnsA({
            { name = "arecord.test", address = "1.2.3.4" },
            { name = "arecord.test", address = "5.6.7.8" },
          })

          assert.same({
            healthy = true,
            weight = {
              total = 100,
              available = 100,
              unavailable = 0
            },
            hosts = {
              {
                host = "127.0.0.1",
                port = 8000,
                dns = "A",
                nodeWeight = 100,
                weight = {
                  total = 100,
                  available = 100,
                  unavailable = 0
                },
                addresses = {
                  {
                    healthy = true,
                    ip = "127.0.0.1",
                    port = 8000,
                    weight = 100
                  },
                },
              },
            },
          }, b:getStatus())

          add_target(b, "arecord.test", 8001, 25)
          assert.same({
            healthy = true,
            weight = {
              total = 150,
              available = 150,
              unavailable = 0
            },
            hosts = {
              {
                host = "127.0.0.1",
                port = 8000,
                dns = "A",
                nodeWeight = 100,
                weight = {
                  total = 100,
                  available = 100,
                  unavailable = 0
                },
                addresses = {
                  {
                    healthy = true,
                    ip = "127.0.0.1",
                    port = 8000,
                    weight = 100
                  },
                },
              },
              {
                host = "arecord.test",
                port = 8001,
                dns = "A",
                nodeWeight = 25,
                weight = {
                  total = 50,
                  available = 50,
                  unavailable = 0
                },
                addresses = {
                  {
                    healthy = true,
                    ip = "1.2.3.4",
                    port = 8001,
                    weight = 25
                  },
                  {
                    healthy = true,
                    ip = "5.6.7.8",
                    port = 8001,
                    weight = 25
                  },
                },
              },
            },
          }, b:getStatus())
        end)

        it("switching address availability",function()
          dnsA({
            { name = "arecord.test", address = "1.2.3.4" },
            { name = "arecord.test", address = "5.6.7.8" },
          })

          assert.same({
            healthy = true,
            weight = {
              total = 100,
              available = 100,
              unavailable = 0
            },
            hosts = {
              {
                host = "127.0.0.1",
                port = 8000,
                dns = "A",
                nodeWeight = 100,
                weight = {
                  total = 100,
                  available = 100,
                  unavailable = 0
                },
                addresses = {
                  {
                    healthy = true,
                    ip = "127.0.0.1",
                    port = 8000,
                    weight = 100
                  },
                },
              },
            },
          }, b:getStatus())

          add_target(b, "arecord.test", 8001, 25)
          assert.same({
            healthy = true,
            weight = {
              total = 150,
              available = 150,
              unavailable = 0
            },
            hosts = {
              {
                host = "127.0.0.1",
                port = 8000,
                dns = "A",
                nodeWeight = 100,
                weight = {
                  total = 100,
                  available = 100,
                  unavailable = 0
                },
                addresses = {
                  {
                    healthy = true,
                    ip = "127.0.0.1",
                    port = 8000,
                    weight = 100
                  },
                },
              },
              {
                host = "arecord.test",
                port = 8001,
                dns = "A",
                nodeWeight = 25,
                weight = {
                  total = 50,
                  available = 50,
                  unavailable = 0
                },
                addresses = {
                  {
                    healthy = true,
                    ip = "1.2.3.4",
                    port = 8001,
                    weight = 25
                  },
                  {
                    healthy = true,
                    ip = "5.6.7.8",
                    port = 8001,
                    weight = 25
                  },
                },
              },
            },
          }, b:getStatus())

          -- switch to unavailable
          assert(b:setAddressStatus(b:findAddress("1.2.3.4", 8001, "arecord.test"), false))
          add_target(b, "arecord.test", 8001, 25)
          assert.same({
            healthy = true,
            weight = {
              total = 150,
              available = 125,
              unavailable = 25
            },
            hosts = {
              {
                host = "127.0.0.1",
                port = 8000,
                dns = "A",
                nodeWeight = 100,
                weight = {
                  total = 100,
                  available = 100,
                  unavailable = 0
                },
                addresses = {
                  {
                    healthy = true,
                    ip = "127.0.0.1",
                    port = 8000,
                    weight = 100
                  },
                },
              },
              {
                host = "arecord.test",
                port = 8001,
                dns = "A",
                nodeWeight = 25,
                weight = {
                  total = 50,
                  available = 25,
                  unavailable = 25
                },
                addresses = {
                  {
                    healthy = false,
                    ip = "1.2.3.4",
                    port = 8001,
                    weight = 25
                  },
                  {
                    healthy = true,
                    ip = "5.6.7.8",
                    port = 8001,
                    weight = 25
                  },
                },
              },
            },
          }, b:getStatus())

          -- switch to available
          assert(b:setAddressStatus(b:findAddress("1.2.3.4", 8001, "arecord.test"), true))
          assert.same({
            healthy = true,
            weight = {
              total = 150,
              available = 150,
              unavailable = 0
            },
            hosts = {
              {
                host = "127.0.0.1",
                port = 8000,
                dns = "A",
                nodeWeight = 100,
                weight = {
                  total = 100,
                  available = 100,
                  unavailable = 0
                },
                addresses = {
                  {
                    healthy = true,
                    ip = "127.0.0.1",
                    port = 8000,
                    weight = 100
                  },
                },
              },
              {
                host = "arecord.test",
                port = 8001,
                dns = "A",
                nodeWeight = 25,
                weight = {
                  total = 50,
                  available = 50,
                  unavailable = 0
                },
                addresses = {
                  {
                    healthy = true,
                    ip = "1.2.3.4",
                    port = 8001,
                    weight = 25
                  },
                  {
                    healthy = true,
                    ip = "5.6.7.8",
                    port = 8001,
                    weight = 25
                  },
                },
              },
            },
          }, b:getStatus())
        end)

        it("changing weight of an available address",function()
          dnsA({
            { name = "arecord.test", address = "1.2.3.4" },
            { name = "arecord.test", address = "5.6.7.8" },
          })

          add_target(b, "arecord.test", 8001, 25)
          assert.same({
            healthy = true,
            weight = {
              total = 150,
              available = 150,
              unavailable = 0
            },
            hosts = {
              {
                host = "127.0.0.1",
                port = 8000,
                dns = "A",
                nodeWeight = 100,
                weight = {
                  total = 100,
                  available = 100,
                  unavailable = 0
                },
                addresses = {
                  {
                    healthy = true,
                    ip = "127.0.0.1",
                    port = 8000,
                    weight = 100
                  },
                },
              },
              {
                host = "arecord.test",
                port = 8001,
                dns = "A",
                nodeWeight = 25,
                weight = {
                  total = 50,
                  available = 50,
                  unavailable = 0
                },
                addresses = {
                  {
                    healthy = true,
                    ip = "1.2.3.4",
                    port = 8001,
                    weight = 25
                  },
                  {
                    healthy = true,
                    ip = "5.6.7.8",
                    port = 8001,
                    weight = 25
                  },
                },
              },
            },
          }, b:getStatus())

          add_target(b, "arecord.test", 8001, 50) -- adding again changes weight
          assert.same({
            healthy = true,
            weight = {
              total = 200,
              available = 200,
              unavailable = 0
            },
            hosts = {
              {
                host = "127.0.0.1",
                port = 8000,
                dns = "A",
                nodeWeight = 100,
                weight = {
                  total = 100,
                  available = 100,
                  unavailable = 0
                },
                addresses = {
                  {
                    healthy = true,
                    ip = "127.0.0.1",
                    port = 8000,
                    weight = 100
                  },
                },
              },
              {
                host = "arecord.test",
                port = 8001,
                dns = "A",
                nodeWeight = 50,
                weight = {
                  total = 100,
                  available = 100,
                  unavailable = 0
                },
                addresses = {
                  {
                    healthy = true,
                    ip = "1.2.3.4",
                    port = 8001,
                    weight = 50
                  },
                  {
                    healthy = true,
                    ip = "5.6.7.8",
                    port = 8001,
                    weight = 50
                  },
                },
              },
            },
          }, b:getStatus())
        end)

        it("changing weight of an unavailable address",function()
          dnsA({
            { name = "arecord.test", address = "1.2.3.4" },
            { name = "arecord.test", address = "5.6.7.8" },
          })

          add_target(b, "arecord.test", 8001, 25)
          assert.same({
            healthy = true,
            weight = {
              total = 150,
              available = 150,
              unavailable = 0
            },
            hosts = {
              {
                host = "127.0.0.1",
                port = 8000,
                dns = "A",
                nodeWeight = 100,
                weight = {
                  total = 100,
                  available = 100,
                  unavailable = 0
                },
                addresses = {
                  {
                    healthy = true,
                    ip = "127.0.0.1",
                    port = 8000,
                    weight = 100
                  },
                },
              },
              {
                host = "arecord.test",
                port = 8001,
                dns = "A",
                nodeWeight = 25,
                weight = {
                  total = 50,
                  available = 50,
                  unavailable = 0
                },
                addresses = {
                  {
                    healthy = true,
                    ip = "1.2.3.4",
                    port = 8001,
                    weight = 25
                  },
                  {
                    healthy = true,
                    ip = "5.6.7.8",
                    port = 8001,
                    weight = 25
                  },
                },
              },
            },
          }, b:getStatus())

          -- switch to unavailable
          assert(b:setAddressStatus(b:findAddress("1.2.3.4", 8001, "arecord.test"), false))
          assert.same({
            healthy = true,
            weight = {
              total = 150,
              available = 125,
              unavailable = 25
            },
            hosts = {
              {
                host = "127.0.0.1",
                port = 8000,
                dns = "A",
                nodeWeight = 100,
                weight = {
                  total = 100,
                  available = 100,
                  unavailable = 0
                },
                addresses = {
                  {
                    healthy = true,
                    ip = "127.0.0.1",
                    port = 8000,
                    weight = 100
                  },
                },
              },
              {
                host = "arecord.test",
                port = 8001,
                dns = "A",
                nodeWeight = 25,
                weight = {
                  total = 50,
                  available = 25,
                  unavailable = 25
                },
                addresses = {
                  {
                    healthy = false,
                    ip = "1.2.3.4",
                    port = 8001,
                    weight = 25
                  },
                  {
                    healthy = true,
                    ip = "5.6.7.8",
                    port = 8001,
                    weight = 25
                  },
                },
              },
            },
          }, b:getStatus())

          add_target(b, "arecord.test", 8001, 50) -- adding again changes weight
          assert.same({
            healthy = true,
            weight = {
              total = 200,
              available = 150,
              unavailable = 50
            },
            hosts = {
              {
                host = "127.0.0.1",
                port = 8000,
                dns = "A",
                nodeWeight = 100,
                weight = {
                  total = 100,
                  available = 100,
                  unavailable = 0
                },
                addresses = {
                  {
                    healthy = true,
                    ip = "127.0.0.1",
                    port = 8000,
                    weight = 100
                  },
                },
              },
              {
                host = "arecord.test",
                port = 8001,
                dns = "A",
                nodeWeight = 50,
                weight = {
                  total = 100,
                  available = 50,
                  unavailable = 50
                },
                addresses = {
                  {
                    healthy = false,
                    ip = "1.2.3.4",
                    port = 8001,
                    weight = 50
                  },
                  {
                    healthy = true,
                    ip = "5.6.7.8",
                    port = 8001,
                    weight = 50
                  },
                },
              },
            },
          }, b:getStatus())
        end)

      end)

      describe("(SRV)", function()

        it("adding a host",function()
          dnsSRV({
            { name = "srvrecord.test", target = "1.1.1.1", port = 9000, weight = 10 },
            { name = "srvrecord.test", target = "2.2.2.2", port = 9001, weight = 10 },
          })

          add_target(b, "srvrecord.test", 8001, 25)
          assert.same({
            healthy = true,
            weight = {
              total = 120,
              available = 120,
              unavailable = 0
            },
            hosts = {
              {
                host = "127.0.0.1",
                port = 8000,
                dns = "A",
                nodeWeight = 100,
                weight = {
                  total = 100,
                  available = 100,
                  unavailable = 0
                },
                addresses = {
                  {
                    healthy = true,
                    ip = "127.0.0.1",
                    port = 8000,
                    weight = 100
                  },
                },
              },
              {
                host = "srvrecord.test",
                port = 8001,
                dns = "SRV",
                nodeWeight = 25,
                weight = {
                  total = 20,
                  available = 20,
                  unavailable = 0
                },
                addresses = {
                  {
                    healthy = true,
                    ip = "1.1.1.1",
                    port = 9000,
                    weight = 10
                  },
                  {
                    healthy = true,
                    ip = "2.2.2.2",
                    port = 9001,
                    weight = 10
                  },
                },
              },
            },
          }, b:getStatus())
        end)

        it("switching address availability",function()
          dnsSRV({
            { name = "srvrecord.test", target = "1.1.1.1", port = 9000, weight = 10 },
            { name = "srvrecord.test", target = "2.2.2.2", port = 9001, weight = 10 },
          })

          add_target(b, "srvrecord.test", 8001, 25)
          assert.same({
            healthy = true,
            weight = {
              total = 120,
              available = 120,
              unavailable = 0
            },
            hosts = {
              {
                host = "127.0.0.1",
                port = 8000,
                dns = "A",
                nodeWeight = 100,
                weight = {
                  total = 100,
                  available = 100,
                  unavailable = 0
                },
                addresses = {
                  {
                    healthy = true,
                    ip = "127.0.0.1",
                    port = 8000,
                    weight = 100
                  },
                },
              },
              {
                host = "srvrecord.test",
                port = 8001,
                dns = "SRV",
                nodeWeight = 25,
                weight = {
                  total = 20,
                  available = 20,
                  unavailable = 0
                },
                addresses = {
                  {
                    healthy = true,
                    ip = "1.1.1.1",
                    port = 9000,
                    weight = 10
                  },
                  {
                    healthy = true,
                    ip = "2.2.2.2",
                    port = 9001,
                    weight = 10
                  },
                },
              },
            },
          }, b:getStatus())

          -- switch to unavailable
          assert(b:setAddressStatus(b:findAddress("1.1.1.1", 9000, "srvrecord.test"), false))
          assert.same({
            healthy = true,
            weight = {
              total = 120,
              available = 110,
              unavailable = 10
            },
            hosts = {
              {
                host = "127.0.0.1",
                port = 8000,
                dns = "A",
                nodeWeight = 100,
                weight = {
                  total = 100,
                  available = 100,
                  unavailable = 0
                },
                addresses = {
                  {
                    healthy = true,
                    ip = "127.0.0.1",
                    port = 8000,
                    weight = 100
                  },
                },
              },
              {
                host = "srvrecord.test",
                port = 8001,
                dns = "SRV",
                nodeWeight = 25,
                weight = {
                  total = 20,
                  available = 10,
                  unavailable = 10
                },
                addresses = {
                  {
                    healthy = false,
                    ip = "1.1.1.1",
                    port = 9000,
                    weight = 10
                  },
                  {
                    healthy = true,
                    ip = "2.2.2.2",
                    port = 9001,
                    weight = 10
                  },
                },
              },
            },
          }, b:getStatus())

          -- switch to available
          assert(b:setAddressStatus(b:findAddress("1.1.1.1", 9000, "srvrecord.test"), true))
          assert.same({
            healthy = true,
            weight = {
              total = 120,
              available = 120,
              unavailable = 0
            },
            hosts = {
              {
                host = "127.0.0.1",
                port = 8000,
                dns = "A",
                nodeWeight = 100,
                weight = {
                  total = 100,
                  available = 100,
                  unavailable = 0
                },
                addresses = {
                  {
                    healthy = true,
                    ip = "127.0.0.1",
                    port = 8000,
                    weight = 100
                  },
                },
              },
              {
                host = "srvrecord.test",
                port = 8001,
                dns = "SRV",
                nodeWeight = 25,
                weight = {
                  total = 20,
                  available = 20,
                  unavailable = 0
                },
                addresses = {
                  {
                    healthy = true,
                    ip = "1.1.1.1",
                    port = 9000,
                    weight = 10
                  },
                  {
                    healthy = true,
                    ip = "2.2.2.2",
                    port = 9001,
                    weight = 10
                  },
                },
              },
            },
          }, b:getStatus())
        end)

        it("changing weight of an available address (dns update)",function()
          local record = dnsSRV({
            { name = "srvrecord.test", target = "1.1.1.1", port = 9000, weight = 10 },
            { name = "srvrecord.test", target = "2.2.2.2", port = 9001, weight = 10 },
          })

          add_target(b, "srvrecord.test", 8001, 10)
          assert.same({
            healthy = true,
            weight = {
              total = 120,
              available = 120,
              unavailable = 0
            },
            hosts = {
              {
                host = "127.0.0.1",
                port = 8000,
                dns = "A",
                nodeWeight = 100,
                weight = {
                  total = 100,
                  available = 100,
                  unavailable = 0
                },
                addresses = {
                  {
                    healthy = true,
                    ip = "127.0.0.1",
                    port = 8000,
                    weight = 100
                  },
                },
              },
              {
                host = "srvrecord.test",
                port = 8001,
                dns = "SRV",
                nodeWeight = 10,
                weight = {
                  total = 20,
                  available = 20,
                  unavailable = 0
                },
                addresses = {
                  {
                    healthy = true,
                    ip = "1.1.1.1",
                    port = 9000,
                    weight = 10
                  },
                  {
                    healthy = true,
                    ip = "2.2.2.2",
                    port = 9001,
                    weight = 10
                  },
                },
              },
            },
          }, b:getStatus())

          dnsExpire(record)
          dnsSRV({
            { name = "srvrecord.test", target = "1.1.1.1", port = 9000, weight = 20 },
            { name = "srvrecord.test", target = "2.2.2.2", port = 9001, weight = 20 },
          })
          targets.resolve_targets(b.targets)  -- touch all addresses to force dns renewal
          add_target(b, "srvrecord.test", 8001, 99) -- add again to update nodeWeight

          assert.same({
            healthy = true,
            weight = {
              total = 140,
              available = 140,
              unavailable = 0
            },
            hosts = {
              {
                host = "127.0.0.1",
                port = 8000,
                dns = "A",
                nodeWeight = 100,
                weight = {
                  total = 100,
                  available = 100,
                  unavailable = 0
                },
                addresses = {
                  {
                    healthy = true,
                    ip = "127.0.0.1",
                    port = 8000,
                    weight = 100
                  },
                },
              },
              {
                host = "srvrecord.test",
                port = 8001,
                dns = "SRV",
                nodeWeight = 99,
                weight = {
                  total = 40,
                  available = 40,
                  unavailable = 0
                },
                addresses = {
                  {
                    healthy = true,
                    ip = "1.1.1.1",
                    port = 9000,
                    weight = 20
                  },
                  {
                    healthy = true,
                    ip = "2.2.2.2",
                    port = 9001,
                    weight = 20
                  },
                },
              },
            },
          }, b:getStatus())
        end)

        it("changing weight of an unavailable address (dns update)",function()
          local record = dnsSRV({
            { name = "srvrecord.test", target = "1.1.1.1", port = 9000, weight = 10 },
            { name = "srvrecord.test", target = "2.2.2.2", port = 9001, weight = 10 },
          })

          add_target(b, "srvrecord.test", 8001, 25)
          assert.same({
            healthy = true,
            weight = {
              total = 120,
              available = 120,
              unavailable = 0
            },
            hosts = {
              {
                host = "127.0.0.1",
                port = 8000,
                dns = "A",
                nodeWeight = 100,
                weight = {
                  total = 100,
                  available = 100,
                  unavailable = 0
                },
                addresses = {
                  {
                    healthy = true,
                    ip = "127.0.0.1",
                    port = 8000,
                    weight = 100
                  },
                },
              },
              {
                host = "srvrecord.test",
                port = 8001,
                dns = "SRV",
                nodeWeight = 25,
                weight = {
                  total = 20,
                  available = 20,
                  unavailable = 0
                },
                addresses = {
                  {
                    healthy = true,
                    ip = "1.1.1.1",
                    port = 9000,
                    weight = 10
                  },
                  {
                    healthy = true,
                    ip = "2.2.2.2",
                    port = 9001,
                    weight = 10
                  },
                },
              },
            },
          }, b:getStatus())

          -- switch to unavailable
          assert(b:setAddressStatus(b:findAddress("2.2.2.2", 9001, "srvrecord.test"), false))
          assert.same({
            healthy = true,
            weight = {
              total = 120,
              available = 110,
              unavailable = 10
            },
            hosts = {
              {
                host = "127.0.0.1",
                port = 8000,
                dns = "A",
                nodeWeight = 100,
                weight = {
                  total = 100,
                  available = 100,
                  unavailable = 0
                },
                addresses = {
                  {
                    healthy = true,
                    ip = "127.0.0.1",
                    port = 8000,
                    weight = 100
                  },
                },
              },
              {
                host = "srvrecord.test",
                port = 8001,
                dns = "SRV",
                nodeWeight = 25,
                weight = {
                  total = 20,
                  available = 10,
                  unavailable = 10
                },
                addresses = {
                  {
                    healthy = true,
                    ip = "1.1.1.1",
                    port = 9000,
                    weight = 10
                  },
                  {
                    healthy = false,
                    ip = "2.2.2.2",
                    port = 9001,
                    weight = 10
                  },
                },
              },
            },
          }, b:getStatus())

          -- update weight, through dns renewal
          dnsExpire(record)
          dnsSRV({
            { name = "srvrecord.test", target = "1.1.1.1", port = 9000, weight = 20 },
            { name = "srvrecord.test", target = "2.2.2.2", port = 9001, weight = 20 },
          })
          targets.resolve_targets(b.targets)  -- touch all addresses to force dns renewal
          add_target(b, "srvrecord.test", 8001, 99) -- add again to update nodeWeight

          assert.same({
            healthy = true,
            weight = {
              total = 140,
              available = 120,
              unavailable = 20
            },
            hosts = {
              {
                host = "127.0.0.1",
                port = 8000,
                dns = "A",
                nodeWeight = 100,
                weight = {
                  total = 100,
                  available = 100,
                  unavailable = 0
                },
                addresses = {
                  {
                    healthy = true,
                    ip = "127.0.0.1",
                    port = 8000,
                    weight = 100
                  },
                },
              },
              {
                host = "srvrecord.test",
                port = 8001,
                dns = "SRV",
                nodeWeight = 99,
                weight = {
                  total = 40,
                  available = 20,
                  unavailable = 20
                },
                addresses = {
                  {
                    healthy = true,
                    ip = "1.1.1.1",
                    port = 9000,
                    weight = 20
                  },
                  {
                    healthy = false,
                    ip = "2.2.2.2",
                    port = 9001,
                    weight = 20
                  },
                },
              },
            },
          }, b:getStatus())
        end)

      end)

    end)


    describe("getpeer() upstream use_srv_name = false", function()

      local b

      before_each(function()
        upstream_index = upstream_index + 1
        local upname="upstream_" .. upstream_index

        local my_upstream = { id=upname, name=upname, ws_id=ws_id, slots=10, healthchecks=hc_defaults, algorithm=algorithm, use_srv_name = false }
        b = (balancers.create_balancer(my_upstream, true))
      end)

      after_each(function()
        b = nil
      end)


      it("returns expected results/types when using SRV with name ('useSRVname=false')", function()
        dnsA({
          { name = "getkong.test", address = "1.2.3.4" },
        })
        dnsSRV({
          { name = "konghq.test", target = "getkong.test", port = 2, weight = 3 },
        })
        add_target(b, "konghq.test", 8000, 50)
        local ip, port, hostname, handle = b:getPeer(true, nil, "a string")
        assert.equal("1.2.3.4", ip)
        assert.equal(2, port)
        assert.equal("konghq.test", hostname)
        assert.not_nil(handle)
      end)
    end)


    describe("getpeer() upstream use_srv_name = true", function()

      local b

      before_each(function()
        upstream_index = upstream_index + 1
        local upname="upstream_" .. upstream_index
        local my_upstream = { id=upname, name=upname, ws_id=ws_id, slots=10, healthchecks=hc_defaults, algorithm=algorithm, use_srv_name = true }
        b = (balancers.create_balancer(my_upstream, true))
      end)

      after_each(function()
        b = nil
      end)


      it("returns expected results/types when using SRV with name ('useSRVname=true')", function()
        dnsA({
          { name = "getkong.test", address = "1.2.3.4" },
        })
        dnsSRV({
          { name = "konghq.test", target = "getkong.test", port = 2, weight = 3 },
        })
        add_target(b, "konghq.test", 8000, 50)
        local ip, port, hostname, handle = b:getPeer(true, nil, "a string")
        assert.equal("1.2.3.4", ip)
        assert.equal(2, port)
        assert.equal("getkong.test", hostname)
        assert.not_nil(handle)
      end)
    end)


    describe("getpeer()", function()

      local b

      before_each(function()
        b = new_balancer(algorithm)
        b.healthThreshold = 50
        b.useSRVname = false
      end)

      after_each(function()
        b = nil
      end)


      it("returns expected results/types when using SRV with IP", function()
        dnsSRV({
          { name = "konghq.test", target = "1.1.1.1", port = 2, weight = 3 },
        })
        add_target(b, "konghq.test", 8000, 50)
        local ip, port, hostname, handle = b:getPeer(true, nil, "a string")
        assert.equal("1.1.1.1", ip)
        assert.equal(2, port)
        assert.equal("konghq.test", hostname)
        assert.not_nil(handle)
      end)


      it("returns expected results/types when using SRV with name ('useSRVname=false')", function()
        dnsA({
          { name = "getkong.test", address = "1.2.3.4" },
        })
        dnsSRV({
          { name = "konghq.test", target = "getkong.test", port = 2, weight = 3 },
        })
        add_target(b, "konghq.test", 8000, 50)
        local ip, port, hostname, handle = b:getPeer(true, nil, "a string")
        assert.equal("1.2.3.4", ip)
        assert.equal(2, port)
        assert.equal("konghq.test", hostname)
        assert.not_nil(handle)
      end)


      it("returns expected results/types when using SRV with name ('useSRVname=true')", function()
        b.useSRVname = true -- override setting specified when creating

        dnsA({
          { name = "getkong.test", address = "1.2.3.4" },
        })
        dnsSRV({
          { name = "konghq.test", target = "getkong.test", port = 2, weight = 3 },
        })
        add_target(b, "konghq.test", 8000, 50)
        local ip, port, hostname, handle = b:getPeer(true, nil, "a string")
        assert.equal("1.2.3.4", ip)
        assert.equal(2, port)
        assert.equal("getkong.test", hostname)
        assert.not_nil(handle)
      end)


      it("returns expected results/types when using A", function()
        dnsA({
          { name = "getkong.test", address = "1.2.3.4" },
        })
        add_target(b, "getkong.test", 8000, 50)
        local ip, port, hostname, handle = b:getPeer(true, nil, "another string")
        assert.equal("1.2.3.4", ip)
        assert.equal(8000, port)
        assert.equal("getkong.test", hostname)
        assert.not_nil(handle)
      end)


      it("returns expected results/types when using IPv4", function()
        add_target(b, "4.3.2.1", 8000, 50)
        local ip, port, hostname, handle = b:getPeer(true, nil, "a string")
        assert.equal("4.3.2.1", ip)
        assert.equal(8000, port)
        assert.equal(nil, hostname)
        assert.not_nil(handle)
      end)


      it("returns expected results/types when using IPv6", function()
        add_target(b, "::1", 8000, 50)
        local ip, port, hostname, handle = b:getPeer(true, nil, "just a string")
        assert.equal("[::1]", ip)
        assert.equal(8000, port)
        assert.equal(nil, hostname)
        assert.not_nil(handle)
      end)


      it("fails when there are no addresses added", function()
        assert.same({
            nil, "Balancer is unhealthy", nil, nil,
          }, {
            b:getPeer(true, nil, "any string")
          }
        )
      end)


      it("fails when all addresses are unhealthy", function()
        add_target(b, "127.0.0.1", 8000, 100)
        add_target(b, "127.0.0.2", 8000, 100)
        add_target(b, "127.0.0.3", 8000, 100)
        b:setAddressStatus(b:findAddress("127.0.0.1", 8000, "127.0.0.1"), false)
        b:setAddressStatus(b:findAddress("127.0.0.2", 8000, "127.0.0.2"), false)
        b:setAddressStatus(b:findAddress("127.0.0.3", 8000, "127.0.0.3"), false)
        assert.same({
            nil, "Balancer is unhealthy", nil, nil,
          }, {
            b:getPeer(true, nil, "a client string")
          }
        )
      end)


      it("fails when balancer switches to unhealthy", function()
        add_target(b, "127.0.0.1", 8000, 100)
        add_target(b, "127.0.0.2", 8000, 100)
        add_target(b, "127.0.0.3", 8000, 100)
        assert.not_nil(b:getPeer(true, nil, "any client string here"))

        b:setAddressStatus(b:findAddress("127.0.0.1", 8000, "127.0.0.1"), false)
        b:setAddressStatus(b:findAddress("127.0.0.2", 8000, "127.0.0.2"), false)
        assert.same({
            nil, "Balancer is unhealthy", nil, nil,
          }, {
            b:getPeer(true, nil, "any string here")
          }
        )
      end)


      it("recovers when balancer switches to healthy", function()
        add_target(b, "127.0.0.1", 8000, 100)
        add_target(b, "127.0.0.2", 8000, 100)
        add_target(b, "127.0.0.3", 8000, 100)
        assert.not_nil(b:getPeer(true, nil, "string from the client"))

        b:setAddressStatus(b:findAddress("127.0.0.1", 8000, "127.0.0.1"), false)
        b:setAddressStatus(b:findAddress("127.0.0.2", 8000, "127.0.0.2"), false)
        assert.same({
            nil, "Balancer is unhealthy", nil, nil,
          }, {
            b:getPeer(true, nil, "string from the client")
          }
        )

        b:setAddressStatus(b:findAddress("127.0.0.2", 8000, "127.0.0.2"), true)
        assert.not_nil(b:getPeer(true, nil, "a string"))
      end)


      it("recovers when dns entries are replaced by healthy ones", function()
        local record = dnsA({
          { name = "getkong.test", address = "1.2.3.4", ttl = 2 },
        })
        add_target(b, "getkong.test", 8000, 50)
        assert.not_nil(b:getPeer(true, nil, "from the client"))

        -- mark it as unhealthy
        assert(b:setAddressStatus(b:findAddress("1.2.3.4", 8000, "getkong.test", false)))
        assert.same({
            nil, "Balancer is unhealthy", nil, nil,
          }, {
            b:getPeer(true, nil, "from the client")
          }
        )

        -- update DNS with a new backend IP
        -- balancer should now recover since a new healthy backend is available
        record.expire = 0
        dnsA({
          { name = "getkong.test", address = "5.6.7.8", ttl = 60 },
        })
        targets.resolve_targets(b.targets)

        local timeout = ngx.now() + 5   -- we'll try for 5 seconds
        while true do
          assert(ngx.now() < timeout, "timeout")
          local ip = b:getPeer(true, nil, "from the client")
          if algorithm == "consistent-hashing" then
            if ip ~= nil then
              break  -- expected result, success!
            end
          else
            if ip == "5.6.7.8" then
              break  -- expected result, success!
            end
          end

          ngx.sleep(0)  -- wait a bit before retrying
        end
      end)
    end)


    describe("status:", function()

      local b

      before_each(function()
        b = new_balancer(algorithm)
      end)

      after_each(function()
        b = nil
      end)


      describe("reports DNS source", function()

        it("status report",function()
          add_target(b, "127.0.0.1", 8000, 100)
          add_target(b, "0::1", 8080, 50)
          dnsSRV({
            { name = "srvrecord.test", target = "1.1.1.1", port = 9000, weight = 10 },
            { name = "srvrecord.test", target = "2.2.2.2", port = 9001, weight = 10 },
          })
          add_target(b, "srvrecord.test", 1234, 9999)
          dnsA({
            { name = "getkong.test", address = "5.6.7.8", ttl = 0 },
          })
          add_target(b, "getkong.test", 5678, 1000)
          add_target(b, "notachanceinhell.this.name.exists.konghq.test", 4321, 100)

          local status = b:getStatus()
          table.sort(status.hosts, function(hostA, hostB) return hostA.host < hostB.host end)

          assert.same({
            healthy = true,
            weight = {
              total = 1170,
              available = 1170,
              unavailable = 0
            },
            hosts = {
              {
                host = "0::1",
                port = 8080,
                dns = "AAAA",
                nodeWeight = 50,
                weight = {
                  total = 50,
                  available = 50,
                  unavailable = 0
                },
                addresses = {
                  {
                    healthy = true,
                    ip = "[0::1]",
                    port = 8080,
                    weight = 50
                  },
                },
              },
              {
                host = "127.0.0.1",
                port = 8000,
                dns = "A",
                nodeWeight = 100,
                weight = {
                  total = 100,
                  available = 100,
                  unavailable = 0
                },
                addresses = {
                  {
                    healthy = true,
                    ip = "127.0.0.1",
                    port = 8000,
                    weight = 100
                  },
                },
              },
              {
                host = "getkong.test",
                port = 5678,
                dns = "ttl=0, virtual SRV",
                nodeWeight = 1000,
                weight = {
                  total = 1000,
                  available = 1000,
                  unavailable = 0
                },
                addresses = {
                  {
                    healthy = true,
                    ip = "getkong.test",
                    port = 5678,
                    weight = 1000
                  },
                },
              },
              {
                host = "notachanceinhell.this.name.exists.konghq.test",
                port = 4321,
                dns = "dns server error: 3 name error",
                nodeWeight = 100,
                weight = {
                  total = 0,
                  available = 0,
                  unavailable = 0
                },
                addresses = {},
              },
              {
                host = "srvrecord.test",
                port = 1234,
                dns = "SRV",
                nodeWeight = 9999,
                weight = {
                  total = 20,
                  available = 20,
                  unavailable = 0
                },
                addresses = {
                  {
                    healthy = true,
                    ip = "1.1.1.1",
                    port = 9000,
                    weight = 10
                  },
                  {
                    healthy = true,
                    ip = "2.2.2.2",
                    port = 9001,
                    weight = 10
                  },
                },
              },
            },
          }, status)
        end)
      end)
    end)
  end)
end
