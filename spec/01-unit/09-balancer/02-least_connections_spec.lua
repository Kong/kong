
local dns_utils = require "kong.resty.dns.utils"
local mocker = require "spec.fixtures.mocker"
local utils = require "kong.tools.utils"

local ws_id = utils.uuid()

local client, balancers, targets

local helpers = require "spec.helpers.dns"
--local gettime = helpers.gettime
--local sleep = helpers.sleep
local dnsSRV = function(...) return helpers.dnsSRV(client, ...) end
local dnsA = function(...) return helpers.dnsA(client, ...) end
--local dnsAAAA = function(...) return helpers.dnsAAAA(client, ...) end
--local dnsExpire = helpers.dnsExpire
local t_insert = table.insert


local unset_register = {}
local function setup_block(consistency)
  local cache_table = {}

  local function mock_cache()
    return {
      safe_set = function(self, k, v)
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

  local function register_unsettter(f)
    table.insert(unset_register, f)
  end

  mocker.setup(register_unsettter, {
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

local function unsetup_block()
  for _, f in ipairs(unset_register) do
    f()
  end
end


local upstream_index = 0
local function new_balancer(targets_list)
  upstream_index = upstream_index + 1
  local upname="upstream_" .. upstream_index
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
  local my_upstream = { id=upname, name=upname, ws_id=ws_id, slots=10, healthchecks=hc_defaults, algorithm="least-connections" }
  local b = (balancers.create_balancer(my_upstream, true))

  for _, target in ipairs(targets_list) do
    local name, port, weight = target, nil, nil
    if type(target) == "table" then
      name = target.name or target[1]
      port = target.port or target[2]
      weight = target.weight or target[3]
    end

    table.insert(b.targets, {
      upstream = name or upname,
      balancer = b,
      name = name,
      nameType = dns_utils.hostnameType(name),
      addresses = {},
      port = port or 8000,
      weight = weight or 100,
      totalWeight = 0,
      unavailableWeight = 0,
    })
  end

  targets.resolve_targets(b.targets)
  return b
end

local function validate_lcb(b, debug)
  local available, unavailable = 0, 0
  local bheap = b.algorithm.binaryHeap
  local num_addresses = 0
  for _, target in ipairs(b.targets) do
    for _, addr in ipairs(target.addresses) do
      if bheap:valueByPayload(addr) then
        -- it's in the heap
        assert(not addr.disabled, "should be enabled when in the heap")
        assert(addr.available, "should be available when in the heap")
        available = available + 1
        assert(bheap:valueByPayload(addr) == (addr.connectionCount+1)/addr.weight)
      else
        assert(not addr.disabled, "should be enabled when not in the heap")
        assert(not addr.available, "should not be available when not in the heap")
        unavailable = unavailable + 1
      end
      num_addresses = num_addresses + 1
    end
  end
  assert(available + unavailable == num_addresses, "mismatch in counts")
  return b
end


describe("[least-connections]", function()

  local snapshot

  setup(function()
    _G.package.loaded["kong.resty.dns.client"] = nil -- make sure module is reloaded
    _G.package.loaded["kong.runloop.balancer.targets"] = nil -- make sure module is reloaded

    client = require "kong.resty.dns.client"
    targets = require "kong.runloop.balancer.targets"
    balancers = require "kong.runloop.balancer.balancers"
    local healthcheckers = require "kong.runloop.balancer.healthcheckers"
    healthcheckers.init()
    balancers.init()

    local kong = {}

    _G.kong = kong

    kong.worker_events = require "resty.worker.events"
    kong.worker_events.configure({
      shm = "kong_process_events", -- defined by "lua_shared_dict"
      timeout = 5,            -- life time of event data in shm
      interval = 1,           -- poll interval (seconds)

      wait_interval = 0.010,  -- wait before retry fetching event data
      wait_max = 0.5,         -- max wait time before discarding event
    })

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
      resolvConf = {
        "nameserver 8.8.8.8"
      },
    })
    snapshot = assert:snapshot()
  end)


  after_each(function()
    snapshot:revert()  -- undo any spying/stubbing etc.
    unsetup_block()
    collectgarbage()
    collectgarbage()
  end)



  describe("new()", function()

    it("inserts provided hosts", function()
      dnsA({
        { name = "konghq.com.", address = "1.2.3.4" },
      })
      dnsA({
        { name = "github.com.", address = "1.2.3.4" },
      })
      dnsA({
        { name = "getkong.test.", address = "1.2.3.4" },
      })
      local b = validate_lcb(new_balancer({
        "konghq.com",                                      -- name only, as string
        { name = "github.com" },                           -- name only, as table
        { name = "getkong.test", port = 80, weight = 25 },  -- fully specified, as table
      }))
      assert.equal("konghq.com", b.targets[1].name)
      assert.equal("github.com", b.targets[2].name)
      assert.equal("getkong.test", b.targets[3].name)
    end)
  end)


  describe("getPeer()", function()

    it("honours weights", function()
      dnsSRV({
        { name = "konghq.com.", target = "20.20.20.20", port = 80, weight = 20 },
        { name = "konghq.com.", target = "50.50.50.50", port = 80, weight = 50 },
      })
      local b = validate_lcb(new_balancer({ "konghq.com" }))

      local counts = {}
      local handles = {}
      for i = 1,70 do
        local ip, _, _, handle = b:getPeer()
        counts[ip] = (counts[ip] or 0) + 1
        t_insert(handles, handle)  -- don't let them get GC'ed
      end

      validate_lcb(b)

      assert.same({
        ["20.20.20.20"] = 20,
        ["50.50.50.50"] = 50
      }, counts)
    end)


    it("first returns top weights, on a 0-connection balancer", function()
      dnsSRV({
        { name = "konghq.com.", target = "20.20.20.20", port = 80, weight = 20 },
        { name = "konghq.com.", target = "50.50.50.50", port = 80, weight = 50 },
      })
      local b = validate_lcb(new_balancer({ "konghq.com" }))

      local handles = {}
      local ip, _, handle

      -- first try
      ip, _, _, handle= b:getPeer()
      t_insert(handles, handle)  -- don't let them get GC'ed
      validate_lcb(b)
      assert.equal("50.50.50.50", ip)

      -- second try
      ip, _, _, handle= b:getPeer()
      t_insert(handles, handle)  -- don't let them get GC'ed
      validate_lcb(b)
      assert.equal("50.50.50.50", ip)

      -- third try
      ip, _, _, handle= b:getPeer()
      t_insert(handles, handle)  -- don't let them get GC'ed
      validate_lcb(b)
      assert.equal("20.20.20.20", ip)
    end)


    it("doesn't use unavailable addresses", function()
      dnsSRV({
        { name = "konghq.com.", target = "20.20.20.20", port = 80, weight = 20 },
        { name = "konghq.com.", target = "50.50.50.50", port = 80, weight = 50 },
      })
      local b = validate_lcb(new_balancer({ "konghq.com" }))

      -- mark one as unavailable
      b:setAddressStatus(b:findAddress("50.50.50.50", 80, "konghq.com"), false)
      local counts = {}
      local handles = {}
      for i = 1,70 do
        local ip, _, _, handle = assert(b:getPeer())
        counts[ip] = (counts[ip] or 0) + 1
        t_insert(handles, handle)  -- don't let them get GC'ed
      end

      validate_lcb(b)

      assert.same({
        ["20.20.20.20"] = 70,
        ["50.50.50.50"] = nil,
      }, counts)
    end)


    it("uses reenabled (available) addresses again", function()
      dnsSRV({
        { name = "konghq.com.", target = "20.20.20.20", port = 80, weight = 20 },
        { name = "konghq.com.", target = "50.50.50.50", port = 80, weight = 50 },
      })
      local b = validate_lcb(new_balancer({ "konghq.com" }))

      -- mark one as unavailable
      b:setAddressStatus(b:findAddress("20.20.20.20", 80, "konghq.com"), false)
      local counts = {}
      local handles = {}
      for i = 1,70 do
        local ip, _, _, handle = b:getPeer()
        counts[ip] = (counts[ip] or 0) + 1
        t_insert(handles, handle)  -- don't let them get GC'ed
      end

      validate_lcb(b)

      assert.same({
        ["20.20.20.20"] = nil,
        ["50.50.50.50"] = 70,
      }, counts)

      -- let's do another 70, after resetting
      b:setAddressStatus(b:findAddress("20.20.20.20", 80, "konghq.com"), true)
      for i = 1,70 do
        local ip, _, _, handle = b:getPeer()
        counts[ip] = (counts[ip] or 0) + 1
        t_insert(handles, handle)  -- don't let them get GC'ed
      end

      validate_lcb(b)

      assert.same({
        ["20.20.20.20"] = 40,
        ["50.50.50.50"] = 100,
      }, counts)
    end)


  end)


  describe("retrying getPeer()", function()

    it("does not return already failed addresses", function()
      dnsSRV({
        { name = "konghq.com.", target = "20.20.20.20", port = 80, weight = 20 },
        { name = "konghq.com.", target = "50.50.50.50", port = 80, weight = 50 },
        { name = "konghq.com.", target = "70.70.70.70", port = 80, weight = 70 },
      })
      local b = validate_lcb(new_balancer({ "konghq.com" }))

      local tried = {}
      local ip, _, handle
      -- first try
      ip, _, _, handle = b:getPeer()
      tried[ip] = (tried[ip] or 0) + 1
      validate_lcb(b)


      -- 1st retry
      ip, _, _, handle = b:getPeer(nil, handle)
      assert.is_nil(tried[ip])
      tried[ip] = (tried[ip] or 0) + 1
      validate_lcb(b)

      -- 2nd retry
      ip, _, _, _ = b:getPeer(nil, handle)
      assert.is_nil(tried[ip])
      tried[ip] = (tried[ip] or 0) + 1
      validate_lcb(b)

      assert.same({
        ["20.20.20.20"] = 1,
        ["50.50.50.50"] = 1,
        ["70.70.70.70"] = 1,
      }, tried)
    end)


    it("retries, after all adresses failed, restarts with previously failed ones", function()
      dnsSRV({
        { name = "konghq.com.", target = "20.20.20.20", port = 80, weight = 20 },
        { name = "konghq.com.", target = "50.50.50.50", port = 80, weight = 50 },
        { name = "konghq.com.", target = "70.70.70.70", port = 80, weight = 70 },
      })
      local b = validate_lcb(new_balancer({ "konghq.com" }))

      local tried = {}
      local ip, _, handle

      for i = 1,6 do
        ip, _, _, handle = b:getPeer(nil, handle)
        tried[ip] = (tried[ip] or 0) + 1
        validate_lcb(b)
      end

      assert.same({
        ["20.20.20.20"] = 2,
        ["50.50.50.50"] = 2,
        ["70.70.70.70"] = 2,
      }, tried)
    end)


    it("releases the previous connection", function()
      dnsSRV({
        { name = "konghq.com.", target = "20.20.20.20", port = 80, weight = 20 },
        { name = "konghq.com.", target = "50.50.50.50", port = 80, weight = 50 },
      })
      local b = validate_lcb(new_balancer({ "konghq.com" }))

      local handle -- define outside loop, so it gets reused and released
      for i = 1,70 do
        local _
        _, _, _, handle = b:getPeer(nil, handle)
      end

      validate_lcb(b)

      local ccount = 0
      for _, target in ipairs(b.targets) do
        for _, addr in ipairs(target.addresses) do
          ccount = ccount + addr.connectionCount
        end
      end
      assert.equal(1, ccount)
    end)

  end)


  describe("release()", function()

    it("releases a connection", function()
      dnsSRV({
        { name = "konghq.com.", target = "20.20.20.20", port = 80, weight = 20 },
      })
      local b = validate_lcb(new_balancer({ "konghq.com" }))

      local ip, _, _, handle = b:getPeer()
      assert.equal("20.20.20.20", ip)
      assert.equal(1, b.targets[1].addresses[1].connectionCount)

      handle:release()
      assert.equal(0, b.targets[1].addresses[1].connectionCount)
    end)


    it("releases connection of already disabled/removed address", function()
      dnsSRV({
        { name = "konghq.com.", target = "20.20.20.20", port = 80, weight = 20 },
      })
      local b = validate_lcb(new_balancer({ "konghq.com" }))

      local ip, _, _, handle = b:getPeer()
      assert.equal("20.20.20.20", ip)
      assert.equal(1, b.targets[1].addresses[1].connectionCount)

      -- remove the host and its addresses
      table.remove(b.targets)
      assert.equal(0, #b.targets)

      local addr = handle.address
      handle:release()
      assert.equal(0, addr.connectionCount)
    end)

  end)

end)
