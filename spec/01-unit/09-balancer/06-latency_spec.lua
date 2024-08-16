
local dns_utils = require "kong.resty.dns.utils"
local mocker = require "spec.fixtures.mocker"
local uuid = require "kong.tools.uuid"

local ws_id = uuid.uuid()

local client, balancers, targets

local helpers = require "spec.helpers.dns"
local dnsSRV = function(...) return helpers.dnsSRV(client, ...) end
local dnsA = function(...) return helpers.dnsA(client, ...) end
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
  local my_upstream = { id=upname, name=upname, ws_id=ws_id, slots=10, healthchecks=hc_defaults, algorithm="latency" }
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

local function validate_latency(b, debug)
  local available, unavailable = 0, 0
  local ewma = b.algorithm.ewma
  local ewma_last_touched_at = b.algorithm.ewma_last_touched_at
  local num_addresses = 0
  for _, target in ipairs(b.targets) do
    for _, addr in ipairs(target.addresses) do
      if ewma[addr] then
        assert(not addr.disabled, "should be enabled when in the ewma")
        assert(addr.available, "should be available when in the ewma")
        available = available + 1
        assert.is_not_nil(ewma[addr], "should have an ewma")
        assert.is_not_nil(ewma_last_touched_at[addr], "should have an ewma_last_touched_at")
      else
        assert(not addr.disabled, "should be enabled when not in the ewma")
        assert(not addr.available, "should not be available when not in the ewma")
        unavailable = unavailable + 1
      end
      num_addresses = num_addresses + 1
    end
  end
  assert(available + unavailable == num_addresses, "mismatch in counts")
  return b
end


for _, enable_new_dns_client in ipairs{ false, true } do

describe("[latency]" .. (enable_new_dns_client and "[new dns]" or ""), function()
  local srv_name = enable_new_dns_client and "_test._tcp.konghq.com"
                                         or  "konghq.com"

  local snapshot
  local old_var = ngx.var

  setup(function()
    _G.busted_new_dns_client = enable_new_dns_client

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

    kong.worker_events = require "resty.events.compat"
    kong.worker_events.configure({
      listening = "unix:",
      testing = true,
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
    _G.ngx.var = {}
    setup_block()
    assert(client.init {
      hosts = {},
      resolvConf = {
        "nameserver 198.51.100.0"
      },
      cache_purge = true,
    })
    snapshot = assert:snapshot()
  end)


  after_each(function()
    _G.ngx.var = old_var
    snapshot:revert()  -- undo any spying/stubbing etc.
    unsetup_block()
    collectgarbage()
    collectgarbage()
  end)



  describe("new()", function()

    it("inserts provided hosts", function()
      dnsA({
        { name = "konghq.com", address = "1.2.3.4" },
      })
      dnsA({
        { name = "github.com", address = "1.2.3.4" },
      })
      dnsA({
        { name = "getkong.org", address = "1.2.3.4" },
      })
      local b = validate_latency(new_balancer({
        "konghq.com",                                      -- name only, as string
        { name = "github.com" },                           -- name only, as table
        { name = "getkong.org", port = 80, weight = 25 },  -- fully specified, as table
      }))
      assert.equal("konghq.com", b.targets[1].name)
      assert.equal("github.com", b.targets[2].name)
      assert.equal("getkong.org", b.targets[3].name)
    end)
  end)


  describe("getPeer()", function()

    it("select low latency target", function()
      dnsSRV({
        { name = srv_name, target = "20.20.20.20", port = 80, weight = 20 },
        { name = srv_name, target = "50.50.50.50", port = 80, weight = 20 },
      })
      local b = validate_latency(new_balancer({ srv_name }))

      local counts = {}
      local handles = {}

      local handle_local
      local ctx_local = {}
      for _, target in pairs(b.targets) do
        for _, address in pairs(target.addresses) do
            if address.ip == "20.20.20.20" then
                ngx.var.upstream_response_time = 0.1
                ngx.var.upstream_connect_time = 0.1
                ngx.var.upstream_addr = "20.20.20.20"
            elseif address.ip == "50.50.50.50" then
                ngx.var.upstream_response_time = 0.2
                ngx.var.upstream_connect_time = 0.2
                ngx.var.upstream_addr = "50.50.50.50"
            end
            handle_local = {address = address}
            b:afterBalance(ctx_local, handle_local)
            ngx.sleep(0.01)
            b:afterBalance(ctx_local, handle_local)
        end
      end

      for i = 1,70 do
        local ip, _, _, handle = b:getPeer()
        counts[ip] = (counts[ip] or 0) + 1
        t_insert(handles, handle)  -- don't let them get GC'ed
      end

      validate_latency(b)

      assert.same({
        ["20.20.20.20"] = 70,
      }, counts)
    end)


    it("first returns one, after update latency return another one", function()
      dnsSRV({
        { name = srv_name, target = "20.20.20.20", port = 80, weight = 20 },
        { name = srv_name, target = "50.50.50.50", port = 80, weight = 20 },
      })
      local b = validate_latency(new_balancer({ srv_name }))

      local handles = {}
      local ip, _, handle
      local counts = {}

      -- first try
      ip, _, _, handle= b:getPeer()
      ngx.var.upstream_response_time = 10
      ngx.var.upstream_connect_time = 10
      ngx.var.upstream_addr = ip
      b:afterBalance({}, handle)
      ngx.sleep(0.01)
      b:afterBalance({}, handle)
      counts[ip] = (counts[ip] or 0) + 1
      t_insert(handles, handle)  -- don't let them get GC'ed
      validate_latency(b)

      -- second try
      ip, _, _, handle= b:getPeer()
      ngx.var.upstream_response_time = 20
      ngx.var.upstream_connect_time = 20
      ngx.var.upstream_addr = ip
      b:afterBalance({}, handle)
      ngx.sleep(0.01)
      b:afterBalance({}, handle)
      counts[ip] = (counts[ip] or 0) + 1
      t_insert(handles, handle)  -- don't let them get GC'ed
      validate_latency(b)

      assert.same({
        ["20.20.20.20"] = 1,
        ["50.50.50.50"] = 1,
      }, counts)
    end)


    it("doesn't use unavailable addresses", function()
      dnsSRV({
        { name = srv_name, target = "20.20.20.20", port = 80, weight = 20 },
        { name = srv_name, target = "50.50.50.50", port = 80, weight = 20 },
      })
      local b = validate_latency(new_balancer({ srv_name }))

      -- mark one as unavailable
      b:setAddressStatus(b:findAddress("50.50.50.50", 80, srv_name), false)
      validate_latency(b)
      local counts = {}
      local handles = {}
      for i = 1,70 do
        local ip, _, _, handle = assert(b:getPeer())
        counts[ip] = (counts[ip] or 0) + 1
        t_insert(handles, handle)  -- don't let them get GC'ed
      end

      validate_latency(b)

      assert.same({
        ["20.20.20.20"] = 70,
        ["50.50.50.50"] = nil,
      }, counts)
    end)

    it("long time update ewma address score, ewma will use the most accurate value", function()
      dnsSRV({
        { name = srv_name, target = "20.20.20.20", port = 80, weight = 20 },
        { name = srv_name, target = "50.50.50.50", port = 80, weight = 20 },
      })
      local b = validate_latency(new_balancer({ srv_name }))

      for _, target in pairs(b.targets) do
        for _, address in pairs(target.addresses) do
            if address.ip == "20.20.20.20" then
                ngx.var.upstream_response_time = 0.1
                ngx.var.upstream_connect_time = 0.1
                ngx.var.upstream_addr = "20.20.20.20"
            elseif address.ip == "50.50.50.50" then
                ngx.var.upstream_response_time = 0.2
                ngx.var.upstream_connect_time = 0.2
                ngx.var.upstream_addr = "50.50.50.50"
            end
            local handle_local = {address = address}
            local ctx_local = {}
            b:afterBalance(ctx_local, handle_local)
            ngx.sleep(0.01)
            b:afterBalance(ctx_local, handle_local)
        end
      end

      validate_latency(b)
      local counts = {}
      local handles = {}
      for i = 1,70 do
        local ip, _, _, handle = assert(b:getPeer())
        counts[ip] = (counts[ip] or 0) + 1
        t_insert(handles, handle)  -- don't let them get GC'ed
      end

      validate_latency(b)

      assert.same({
        ["20.20.20.20"] = 70,
        ["50.50.50.50"] = nil,
      }, counts)

      ngx.sleep(10)

      for _, target in pairs(b.targets) do
        for _, address in pairs(target.addresses) do
            if address.ip == "20.20.20.20" then
                ngx.var.upstream_response_time = 0.2
                ngx.var.upstream_connect_time = 0.2
                ngx.var.upstream_addr = "20.20.20.20"
            elseif address.ip == "50.50.50.50" then
                ngx.var.upstream_response_time = 0.1
                ngx.var.upstream_connect_time = 0.1
                ngx.var.upstream_addr = "50.50.50.50"
            end
            local handle_local = {address = address}
            local ctx_local = {}
            b:afterBalance(ctx_local, handle_local)
            ngx.sleep(0.01)
            b:afterBalance(ctx_local, handle_local)
        end
      end

      for i = 1,70 do
        local ip, _, _, handle = assert(b:getPeer())
        counts[ip] = (counts[ip] or 0) + 1
        t_insert(handles, handle)  -- don't let them get GC'ed
      end

      validate_latency(b)

      assert.same({
        ["20.20.20.20"] = 70,
        ["50.50.50.50"] = 70,
      }, counts)
    end)


    it("uses reenabled (available) addresses again", function()
      dnsSRV({
        { name = srv_name, target = "20.20.20.20", port = 80, weight = 20 },
        { name = srv_name, target = "50.50.50.50", port = 80, weight = 20 },
      })
      local b = validate_latency(new_balancer({ srv_name }))

      -- mark one as unavailable
      b:setAddressStatus(b:findAddress("20.20.20.20", 80, srv_name), false)
      local counts = {}
      local handles = {}
      for i = 1,70 do
        local ip, _, _, handle = b:getPeer()
        counts[ip] = (counts[ip] or 0) + 1
        ngx.var.upstream_response_time = 0.2
        ngx.var.upstream_connect_time = 0.2
        ngx.var.upstream_addr = ip
        b:afterBalance({}, handle)
        ngx.sleep(0.01)
        b:afterBalance({}, handle)
        t_insert(handles, handle)  -- don't let them get GC'ed
      end

      validate_latency(b)

      assert.same({
        ["20.20.20.20"] = nil,
        ["50.50.50.50"] = 70,
      }, counts)

      -- let's do another 70, after resetting
      b:setAddressStatus(b:findAddress("20.20.20.20", 80, srv_name), true)
      for _, target in pairs(b.targets) do
        for _, address in pairs(target.addresses) do
            if address.ip == "20.20.20.20" then
                ngx.var.upstream_response_time = 0.1
                ngx.var.upstream_connect_time = 0.1
                ngx.var.upstream_addr = "20.20.20.20"
            elseif address.ip == "50.50.50.50" then
                ngx.var.upstream_response_time = 0.2
                ngx.var.upstream_connect_time = 0.2
                ngx.var.upstream_addr = "50.50.50.50"
            end
            local handle_local= {address = address}
            local ctx_local = {}
            b:afterBalance(ctx_local, handle_local)
            ngx.sleep(0.01)
            b:afterBalance(ctx_local, handle_local)
        end
      end

      local ip, _, _, handle = b:getPeer()
      counts[ip] = (counts[ip] or 0) + 1
      t_insert(handles, handle)  -- don't let them get GC'ed
      validate_latency(b)
      assert.same({
        ["20.20.20.20"] = 1,
        ["50.50.50.50"] = 70,
      }, counts)

      ngx.sleep(3)

      for _, target in pairs(b.targets) do
        for _, address in pairs(target.addresses) do
            if address.ip == "20.20.20.20" then
                ngx.var.upstream_response_time = 2
                ngx.var.upstream_connect_time = 2
                ngx.var.upstream_addr = "20.20.20.20"
            elseif address.ip == "50.50.50.50" then
                ngx.var.upstream_response_time = 0.1
                ngx.var.upstream_connect_time = 0.1
                ngx.var.upstream_addr = "50.50.50.50"
            end
            local handle_local = {address = address}
            local ctx_local = {}
            b:afterBalance(ctx_local, handle_local)
            ngx.sleep(0.1)
            b:afterBalance(ctx_local, handle_local)
        end
      end

      for i = 1,70 do
        local ip, _, _, handle = b:getPeer()
        counts[ip] = (counts[ip] or 0) + 1
        t_insert(handles, handle)  -- don't let them get GC'ed
      end

      validate_latency(b)

      assert.same({
        ["20.20.20.20"] = 1,
        ["50.50.50.50"] = 140,
      }, counts)
    end)


  end)


  describe("retrying getPeer()", function()

    it("does not return already failed addresses", function()
      dnsSRV({
        { name = srv_name, target = "20.20.20.20", port = 80, weight = 20 },
        { name = srv_name, target = "50.50.50.50", port = 80, weight = 50 },
        { name = srv_name, target = "70.70.70.70", port = 80, weight = 70 },
      })
      local b = validate_latency(new_balancer({ srv_name }))

      local tried = {}
      local ip, _, handle
      -- first try
      ip, _, _, handle = b:getPeer()
      tried[ip] = (tried[ip] or 0) + 1
      validate_latency(b)


      -- 1st retry
      ip, _, _, handle = b:getPeer(nil, handle)
      assert.is_nil(tried[ip])
      tried[ip] = (tried[ip] or 0) + 1
      validate_latency(b)

      -- 2nd retry
      ip, _, _, _ = b:getPeer(nil, handle)
      assert.is_nil(tried[ip])
      tried[ip] = (tried[ip] or 0) + 1
      validate_latency(b)

      assert.same({
        ["20.20.20.20"] = 1,
        ["50.50.50.50"] = 1,
        ["70.70.70.70"] = 1,
      }, tried)
    end)


    it("retries, after all addresses failed, retry end", function()
      dnsSRV({
        { name = srv_name, target = "20.20.20.20", port = 80, weight = 20 },
        { name = srv_name, target = "50.50.50.50", port = 80, weight = 50 },
        { name = srv_name, target = "70.70.70.70", port = 80, weight = 70 },
      })
      local b = validate_latency(new_balancer({ srv_name }))

      local tried = {}
      local ip, _, handle

      for i = 1,4 do
        ip, _, _, handle = b:getPeer(nil, handle)
        if ip then
          tried[ip] = (tried[ip] or 0) + 1
          validate_latency(b)
        end

      end

      assert.same({
        ["20.20.20.20"] = 1,
        ["50.50.50.50"] = 1,
        ["70.70.70.70"] = 1,
      }, tried)
    end)

  end)
end)

end
