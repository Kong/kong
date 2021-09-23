
assert:set_parameter("TableFormatLevel", 5) -- when displaying tables, set a bigger default depth


------------------------
-- START TEST HELPERS --
------------------------
local client, balancer

local helpers = require "spec.test_helpers"
local gettime = helpers.gettime
local sleep = helpers.sleep
local dnsSRV = function(...) return helpers.dnsSRV(client, ...) end
local dnsA = function(...) return helpers.dnsA(client, ...) end
local dnsAAAA = function(...) return helpers.dnsAAAA(client, ...) end


-- creates a hash table with "address:port" keys and as value the number of indices
local function count_indices(balancer)
  local r = {}
  local continuum = balancer:_get_continuum()
  for _, address in pairs(continuum) do
    local key = tostring(address.ip)
    if key:find(":",1,true) then
      --print("available: ", address.available)
      key = "["..key.."]:"..address.port
    else
      key = key..":"..address.port
    end
    r[key] = (r[key] or 0) + 1
  end
  return r
end

-- copies the wheel to a list with ip, port and hostname in the field values.
-- can be used for before/after comparison
local copyWheel = function(b)
  local copy = {}
  local continuum = b:_get_continuum()
  for i, address in pairs(continuum) do
    copy[i] = i.." - "..address.ip.." @ "..address.port.." ("..address.host.hostname..")"
  end
  return copy
end
----------------------
-- END TEST HELPERS --
----------------------


describe("[consistent_hashing]", function()

  local snapshot

  setup(function()
    _G.package.loaded["resty.dns.client"] = nil -- make sure module is reloaded
    balancer = require "resty.dns.balancer.consistent_hashing"
    client = require "resty.dns.client"
  end)

  before_each(function()
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
    collectgarbage()
    collectgarbage()
  end)

  it("ringbalancer with a running timer gets GC'ed", function()
    local b = balancer.new({
      dns = client,
      wheelSize = 15,
      requery = 0.1,
    })
    assert(b:addHost("this.will.not.be.found", 80, 10))

    local tracker = setmetatable({ b }, {__mode = "v"})
    local t = 0
    while t<10 do
      if t>0.5 then -- let the timer do its work, only dismiss after 0.5 seconds
        -- luacheck: push no unused
        b = nil -- mark it for GC
        -- luacheck: pop
      end
      sleep(0.1)
      collectgarbage()
      if not next(tracker) then
        break
      end
      t = t + 0.1
    end
    assert(t < 10, "timeout while waiting for balancer to be GC'ed")
  end)

  describe("getting targets", function()
    it("gets an IP address and port number; consistent hashing", function()
      dnsA({
        { name = "mashape.com", address = "1.2.3.4" },
      })
      dnsA({
        { name = "getkong.org", address = "5.6.7.8" },
      })
      local b = balancer.new({
        hosts = {
          {name = "mashape.com", port = 123, weight = 10},
          {name = "getkong.org", port = 321, weight = 5},
        },
        dns = client,
        wheelSize = (1000),
      })
      -- run down the wheel, hitting all indices once
      local res = {}
      for n = 1, 1500 do
        local addr, port, host = b:getPeer(false, nil, tostring(n))
        res[addr..":"..port] = (res[addr..":"..port] or 0) + 1
        res[host..":"..port] = (res[host..":"..port] or 0) + 1
      end
      -- weight distribution may vary up to 10% when using ketama algorithm
      assert.is_true(res["1.2.3.4:123"] > 900)
      assert.is_true(res["1.2.3.4:123"] < 1100)
      assert.is_true(res["5.6.7.8:321"] > 450)
      assert.is_true(res["5.6.7.8:321"] < 550)
      -- hit one index 15 times
      res = {}
      local hash = tostring(6)  -- just pick one
      for _ = 1, 15 do
        local addr, port, host = b:getPeer(false, nil, hash)
        res[addr..":"..port] = (res[addr..":"..port] or 0) + 1
        res[host..":"..port] = (res[host..":"..port] or 0) + 1
      end
      assert(15 == res["1.2.3.4:123"] or nil == res["1.2.3.4:123"], "mismatch")
      assert(15 == res["mashape.com:123"] or nil == res["mashape.com:123"], "mismatch")
      assert(15 == res["5.6.7.8:321"] or nil == res["5.6.7.8:321"], "mismatch")
      assert(15 == res["getkong.org:321"] or nil == res["getkong.org:321"], "mismatch")
    end)
    it("evaluate the change in the continuum", function()
      local res1 = {}
      local res2 = {}
      local res3 = {}
      local b = balancer.new({
        hosts = {
          {name = "10.0.0.1", port = 1, weight = 100},
          {name = "10.0.0.2", port = 2, weight = 100},
          {name = "10.0.0.3", port = 3, weight = 100},
          {name = "10.0.0.4", port = 4, weight = 100},
          {name = "10.0.0.5", port = 5, weight = 100},
        },
        dns = client,
        wheelSize = 5000,
      })
      for n = 1, 10000 do
        local addr, port = b:getPeer(false, nil, n)
        res1[n] = { ip = addr, port = port }
      end
      b:addHost("10.0.0.6", 6, 100)
      for n = 1, 10000 do
        local addr, port = b:getPeer(false, nil, n)
        res2[n] = { ip = addr, port = port }
      end

      local dif = 0
      for n = 1, 10000 do
        if res1[n].ip ~= res2[n].ip or res1[n].port ~= res2[n].port then
          dif = dif + 1
        end
      end

      -- increasing the number of addresses from 5 to 6 should change 49% of
      -- targets if we were using a simple distribution, like an array.
      -- anyway, we should be below than 20%.
      assert((dif/100) < 49, "it should be better than a simple distribution")
      assert((dif/100) < 20, "it is still to much change ")


      b:addHost("10.0.0.7", 7, 100)
      b:addHost("10.0.0.8", 8, 100)
      for n = 1, 10000 do
        local addr, port = b:getPeer(false, nil, n)
        res3[n] = { ip = addr, port = port }
      end

      dif = 0
      local dif2 = 0
      for n = 1, 10000 do
        if res1[n].ip ~= res3[n].ip or res1[n].port ~= res3[n].port then
          dif = dif + 1
        end
        if res2[n].ip ~= res3[n].ip or res2[n].port ~= res3[n].port then
          dif2 = dif2 + 1
        end
      end
      -- increasing the number of addresses from 5 to 8 should change 83% of
      -- targets, and from 6 to 8, 76%, if we were using a simple distribution,
      -- like an array.
      -- either way, we should be below than 40% and 25%.
      assert((dif/100) < 83, "it should be better than a simple distribution")
      assert((dif/100) < 40, "it is still to much change ")
      assert((dif2/100) < 76, "it should be better than a simple distribution")
      assert((dif2/100) < 25, "it is still to much change ")
    end)
    it("gets an IP address and port number; consistent hashing skips unhealthy addresses", function()
      dnsA({
        { name = "mashape.com", address = "1.2.3.4" },
      })
      dnsA({
        { name = "getkong.org", address = "5.6.7.8" },
      })
      local b = balancer.new({
        hosts = {
          {name = "mashape.com", port = 123, weight = 100},
          {name = "getkong.org", port = 321, weight = 50},
        },
        dns = client,
        wheelSize = 1000,
      })
      -- mark node down
      assert(b:setAddressStatus(false, "1.2.3.4", 123, "mashape.com"))
      -- do a few requests
      local res = {}
      for n = 1, 160 do
        local addr, port, host = b:getPeer(false, nil, n)
        res[addr..":"..port] = (res[addr..":"..port] or 0) + 1
        res[host..":"..port] = (res[host..":"..port] or 0) + 1
      end
      assert.equal(nil, res["1.2.3.4:123"])     -- address got no hits, key never gets initialized
      assert.equal(nil, res["mashape.com:123"]) -- host got no hits, key never gets initialized
      assert.equal(160, res["5.6.7.8:321"])
      assert.equal(160, res["getkong.org:321"])
    end)
    it("does not hit the resolver when 'cache_only' is set", function()
      local record = dnsA({
        { name = "mashape.com", address = "1.2.3.4" },
      })
      local b = balancer.new({
        hosts = { { name = "mashape.com", port = 80, weight = 5 } },
        dns = client,
        wheelSize = 10,
      })
      record.expire = gettime() - 1 -- expire current dns cache record
      dnsA({   -- create a new record
        { name = "mashape.com", address = "5.6.7.8" },
      })
      -- create a spy to check whether dns was queried
      spy.on(client, "resolve")
      local hash = "a value to hash"
      local cache_only = true
      local ip, port, host = b:getPeer(cache_only, nil, hash)
      assert.spy(client.resolve).Not.called_with("mashape.com",nil, nil)
      assert.equal("1.2.3.4", ip)  -- initial un-updated ip address
      assert.equal(80, port)
      assert.equal("mashape.com", host)
    end)
  end)

  describe("setting status triggers address-callback", function()
    it("for IP addresses", function()
      local count_add = 0
      local count_remove = 0
      local b
      b = balancer.new({
        hosts = {},  -- no hosts, so balancer is empty
        dns = client,
        wheelSize = 10,
        callback = function(balancer, action, address, ip, port, hostname)
          assert.equal(b, balancer)
          if action == "added" then
            count_add = count_add + 1
          elseif action == "removed" then
            count_remove = count_remove + 1
          elseif action == "health" then  --luacheck: ignore
            -- nothing to do
          else
            error("unknown action received: "..tostring(action))
          end
          if action ~= "health" then
            assert.equals("12.34.56.78", ip)
            assert.equals(123, port)
            assert.equals("12.34.56.78", hostname)
          end
        end
      })
      b:addHost("12.34.56.78", 123, 100)
      ngx.sleep(0.1)
      assert.equal(1, count_add)
      assert.equal(0, count_remove)
      b:removeHost("12.34.56.78", 123)
      ngx.sleep(0.1)
      assert.equal(1, count_add)
      assert.equal(1, count_remove)
    end)
    it("for 1 level dns", function()
      local count_add = 0
      local count_remove = 0
      local b
      b = balancer.new({
        hosts = {},  -- no hosts, so balancer is empty
        dns = client,
        wheelSize = 10,
        callback = function(balancer, action, address, ip, port, hostname)
          assert.equal(b, balancer)
          if action == "added" then
            count_add = count_add + 1
          elseif action == "removed" then
            count_remove = count_remove + 1
          elseif action == "health" then  --luacheck: ignore
            -- nothing to do
          else
            error("unknown action received: "..tostring(action))
          end
          if action ~= "health" then
            assert.equals("12.34.56.78", ip)
            assert.equals(123, port)
            assert.equals("mashape.com", hostname)
          end
        end
      })
      dnsA({
        { name = "mashape.com", address = "12.34.56.78" },
        { name = "mashape.com", address = "12.34.56.78" },
      })
      b:addHost("mashape.com", 123, 100)
      ngx.sleep(0.1)
      assert.equal(2, count_add)
      assert.equal(0, count_remove)
      b:removeHost("mashape.com", 123)
      ngx.sleep(0.1)
      assert.equal(2, count_add)
      assert.equal(2, count_remove)
    end)
    it("for 2+ level dns", function()
      local count_add = 0
      local count_remove = 0
      local b
      b = balancer.new({
        hosts = {},  -- no hosts, so balancer is empty
        dns = client,
        wheelSize = 10,
        callback = function(balancer, action, address, ip, port, hostname)
          assert.equal(b, balancer)
          if action == "added" then
            count_add = count_add + 1
          elseif action == "removed" then
            count_remove = count_remove + 1
          elseif action == "health" then  --luacheck: ignore
            -- nothing to do
          else
            error("unknown action received: "..tostring(action))
          end
          if action ~= "health" then
            assert(ip == "mashape1.com" or ip == "mashape2.com")
            assert(port == 8001 or port == 8002)
            assert.equals("mashape.com", hostname)
          end
        end
      })
      dnsA({
        { name = "mashape1.com", address = "12.34.56.1" },
      })
      dnsA({
        { name = "mashape2.com", address = "12.34.56.2" },
      })
      dnsSRV({
        { name = "mashape.com", target = "mashape1.com", port = 8001, weight = 5 },
        { name = "mashape.com", target = "mashape2.com", port = 8002, weight = 5 },
      })
      b:addHost("mashape.com", 123, 100)
      ngx.sleep(0.1)
      assert.equal(2, count_add)
      assert.equal(0, count_remove)
      b:removeHost("mashape.com", 123)
      ngx.sleep(0.1)
      assert.equal(2, count_add)
      assert.equal(2, count_remove)
    end)
  end)

  describe("wheel manipulation", function()
    it("wheel updates are atomic", function()
      -- testcase for issue #49, see:
      -- https://github.com/Kong/lua-resty-dns-client/issues/49
      local order_of_events = {}
      local b
      b = balancer.new({
        hosts = {},  -- no hosts, so balancer is empty
        dns = client,
        wheelSize = 10,
        callback = function(balancer, action, ip, port, hostname)
          table.insert(order_of_events, "callback")
          -- this callback is called when updating. So yield here and
          -- verify that the second thread does not interfere with
          -- the first update, yielded here.
          ngx.sleep(0.1)
        end
      })
      dnsA({
        { name = "mashape1.com", address = "12.34.56.78" },
      })
      dnsA({
        { name = "mashape2.com", address = "123.45.67.89" },
      })
      local t1 = ngx.thread.spawn(function()
        table.insert(order_of_events, "thread1 start")
        b:addHost("mashape1.com")
        table.insert(order_of_events, "thread1 end")
      end)
      local t2 = ngx.thread.spawn(function()
        table.insert(order_of_events, "thread2 start")
        b:addHost("mashape2.com")
        table.insert(order_of_events, "thread2 end")
      end)
      ngx.thread.wait(t1)
      ngx.thread.wait(t2)
      ngx.sleep(0.1)
      assert.same({
        [1] = 'thread1 start',
        [2] = 'thread1 end',
        [3] = 'thread2 start',
        [4] = 'thread2 end',
        [5] = 'callback',
        [6] = 'callback',
        [7] = 'callback',
      }, order_of_events)
    end)
    it("equal weights and 'fitting' indices", function()
      dnsA({
        { name = "mashape.com", address = "1.2.3.4" },
        { name = "mashape.com", address = "1.2.3.5" },
      })
      local b = balancer.new({
        hosts = {"mashape.com"},
        dns = client,
        wheelSize = 1000,
      })
      local expected = {
        ["1.2.3.4:80"] = 80,
        ["1.2.3.5:80"] = 80,
      }
      assert.are.same(expected, count_indices(b))
    end)
    it("DNS record order has no effect", function()
      dnsA({
        { name = "mashape.com", address = "1.2.3.1" },
        { name = "mashape.com", address = "1.2.3.2" },
        { name = "mashape.com", address = "1.2.3.3" },
        { name = "mashape.com", address = "1.2.3.4" },
        { name = "mashape.com", address = "1.2.3.5" },
        { name = "mashape.com", address = "1.2.3.6" },
        { name = "mashape.com", address = "1.2.3.7" },
        { name = "mashape.com", address = "1.2.3.8" },
        { name = "mashape.com", address = "1.2.3.9" },
        { name = "mashape.com", address = "1.2.3.10" },
      })
      local b = balancer.new({
        hosts = {"mashape.com"},
        dns = client,
        wheelSize = 1000,
      })
      local expected = count_indices(b)
      dnsA({
        { name = "mashape.com", address = "1.2.3.8" },
        { name = "mashape.com", address = "1.2.3.3" },
        { name = "mashape.com", address = "1.2.3.1" },
        { name = "mashape.com", address = "1.2.3.2" },
        { name = "mashape.com", address = "1.2.3.4" },
        { name = "mashape.com", address = "1.2.3.5" },
        { name = "mashape.com", address = "1.2.3.6" },
        { name = "mashape.com", address = "1.2.3.9" },
        { name = "mashape.com", address = "1.2.3.10" },
        { name = "mashape.com", address = "1.2.3.7" },
      })
      b = balancer.new({
        hosts = {"mashape.com"},
        dns = client,
        wheelSize = 1000,
      })

      assert.are.same(expected, count_indices(b))
    end)
    it("changing hostname order has no effect", function()
      dnsA({
        { name = "mashape.com", address = "1.2.3.1" },
      })
      dnsA({
        { name = "getkong.org", address = "1.2.3.2" },
      })
      local b = balancer.new {
        hosts = {"mashape.com", "getkong.org"},
        dns = client,
        wheelSize = 1000,
      }
      local expected = count_indices(b)
      b = balancer.new({
        hosts = {"getkong.org", "mashape.com"},  -- changed host order
        dns = client,
        wheelSize = 1000,
      })
      assert.are.same(expected, count_indices(b))
    end)
    it("adding a host", function()
      dnsA({
        { name = "mashape.com", address = "1.2.3.4" },
        { name = "mashape.com", address = "1.2.3.5" },
      })
      dnsAAAA({
        { name = "getkong.org", address = "::1" },
      })
      local b = balancer.new({
        hosts = { { name = "mashape.com", port = 80, weight = 5 } },
        dns = client,
        wheelSize = 2000,
      })
      b:addHost("getkong.org", 8080, 10 )
      local expected = {
        ["1.2.3.4:80"] = 80,
        ["1.2.3.5:80"] = 80,
        ["[::1]:8080"] = 160,
      }
      assert.are.same(expected, count_indices(b))
    end)
    it("removing the last host", function()
      dnsA({
        { name = "mashape.com", address = "1.2.3.4" },
        { name = "mashape.com", address = "1.2.3.5" },
      })
      dnsAAAA({
        { name = "getkong.org", address = "::1" },
      })
      local b = balancer.new({
        dns = client,
        wheelSize = 1000,
      })
      b:addHost("mashape.com", 80, 5)
      b:addHost("getkong.org", 8080, 10)
      b:removeHost("getkong.org", 8080)
      b:removeHost("mashape.com", 80)
    end)
    it("weight change updates properly", function()
      dnsA({
        { name = "mashape.com", address = "1.2.3.4" },
        { name = "mashape.com", address = "1.2.3.5" },
      })
      dnsAAAA({
        { name = "getkong.org", address = "::1" },
      })
      local b = balancer.new({
        dns = client,
        wheelSize = 1000,
      })
      b:addHost("mashape.com", 80, 10)
      b:addHost("getkong.org", 80, 10)
      local count = count_indices(b)
      -- 2 hosts -> 320 points
      -- resolved to 3 addresses with same weight -> 106 points each
      assert.same({
          ["1.2.3.4:80"] = 106,
          ["1.2.3.5:80"] = 106,
          ["[::1]:80"]   = 106,
      }, count)

      b:addHost("mashape.com", 80, 25)
      count = count_indices(b)
      -- 2 hosts -> 320 points
      -- 1 with 83% of weight resolved to 2 addresses -> 133 points each addr
      -- 1 with 16% of weight resolved to 1 address -> 53 points
      assert.same({
          ["1.2.3.4:80"] = 133,
          ["1.2.3.5:80"] = 133,
          ["[::1]:80"]   = 53,
      }, count)
    end)
    it("weight change ttl=0 record, updates properly", function()
      -- mock the resolve/toip methods
      local old_resolve = client.resolve
      local old_toip = client.toip
      finally(function()
          client.resolve = old_resolve
          client.toip = old_toip
        end)
      client.resolve = function(name, ...)
        if name == "mashape.com" then
          local record = dnsA({
            { name = "mashape.com", address = "1.2.3.4", ttl = 0 },
          })
          return record
        else
          return old_resolve(name, ...)
        end
      end
      client.toip = function(name, ...)
        if name == "mashape.com" then
          return "1.2.3.4", ...
        else
          return old_toip(name, ...)
        end
      end

      -- insert 2nd address
      dnsA({
        { name = "getkong.org", address = "9.9.9.9", ttl = 60*60 },
      })

      local b = balancer.new({
        hosts = {
          { name = "mashape.com", port = 80, weight = 50 },
          { name = "getkong.org", port = 123, weight = 50 },
        },
        dns = client,
        wheelSize = 100,
        ttl0 = 2,
      })

      local count = count_indices(b)
      assert.same({
          ["mashape.com:80"] = 160,
          ["9.9.9.9:123"] = 160,
      }, count)

      -- update weights
      b:addHost("mashape.com", 80, 150)

      count = count_indices(b)
      -- total weight: 200
      -- 2 hosts: 320 points
      -- 75%: 240, 25%: 80
      assert.same({
          ["mashape.com:80"] = 240,
          ["9.9.9.9:123"] = 80,
      }, count)
    end)
    it("weight change for unresolved record, updates properly", function()
      local record = dnsA({
        { name = "really.really.really.does.not.exist.thijsschreijer.nl", address = "1.2.3.4" },
      })
      dnsAAAA({
        { name = "getkong.org", address = "::1" },
      })
      local b = balancer.new({
        dns = client,
        wheelSize = 1000,
        requery = 0.1,
      })
      b:addHost("really.really.really.does.not.exist.thijsschreijer.nl", 80, 10)
      b:addHost("getkong.org", 80, 10)
      local count = count_indices(b)
      assert.same({
          ["1.2.3.4:80"] = 160,
          ["[::1]:80"]   = 160,
      }, count)

      -- expire the existing record
      record.expire = 0
      record.expired = true
      -- do a lookup to trigger the async lookup
      client.resolve("really.really.really.does.not.exist.thijsschreijer.nl", {qtype = client.TYPE_A})
      sleep(1) -- provide time for async lookup to complete

      b:_hit_all() -- hit them all to force renewal

      count = count_indices(b)
      assert.same({
          --["1.2.3.4:80"] = 0,  --> failed to resolve, no more entries
          ["[::1]:80"]   = 320,
      }, count)

      -- update the failed record
      b:addHost("really.really.really.does.not.exist.thijsschreijer.nl", 80, 20)
      -- reinsert a cache entry
      dnsA({
        { name = "really.really.really.does.not.exist.thijsschreijer.nl", address = "1.2.3.4" },
      })
      sleep(2)  -- wait for timer to re-resolve the record

      count = count_indices(b)
      -- 66%: 213 points
      -- 33%: 106 points
      assert.same({
          ["1.2.3.4:80"] = 213,
          ["[::1]:80"]   = 106,
      }, count)
    end)
    it("weight change SRV record, has no effect", function()
      dnsA({
        { name = "mashape.com", address = "1.2.3.4" },
        { name = "mashape.com", address = "1.2.3.5" },
      })
      dnsSRV({
        { name = "gelato.io", target = "1.2.3.6", port = 8001, weight = 5 },
        { name = "gelato.io", target = "1.2.3.6", port = 8002, weight = 5 },
      })
      local b = balancer.new({
        dns = client,
        wheelSize = 1000,
      })
      b:addHost("mashape.com", 80, 10)
      b:addHost("gelato.io", 80, 10)  --> port + weight will be ignored
      local count = count_indices(b)
      local state = copyWheel(b)
      -- 33%: 106 points
      -- 16%: 53 points
      assert.same({
          ["1.2.3.4:80"]   = 106,
          ["1.2.3.5:80"]   = 106,
          ["1.2.3.6:8001"] = 53,
          ["1.2.3.6:8002"] = 53,
      }, count)

      b:addHost("gelato.io", 80, 20)  --> port + weight will be ignored
      count = count_indices(b)
      assert.same({
          ["1.2.3.4:80"]   = 106,
          ["1.2.3.5:80"]   = 106,
          ["1.2.3.6:8001"] = 53,
          ["1.2.3.6:8002"] = 53,
      }, count)
      assert.same(state, copyWheel(b))
    end)
    it("renewed DNS A record; no changes", function()
      local record = dnsA({
        { name = "mashape.com", address = "1.2.3.4" },
        { name = "mashape.com", address = "1.2.3.5" },
      })
      dnsA({
        { name = "getkong.org", address = "9.9.9.9" },
      })
      local b = balancer.new({
        hosts = {
          { name = "mashape.com", port = 80, weight = 5 },
          { name = "getkong.org", port = 123, weight = 10 },
        },
        dns = client,
        wheelSize = 100,
      })
      local state = copyWheel(b)
      record.expire = gettime() -1 -- expire current dns cache record
      dnsA({   -- create a new record (identical)
        { name = "mashape.com", address = "1.2.3.4" },
        { name = "mashape.com", address = "1.2.3.5" },
      })
      -- create a spy to check whether dns was queried
      spy.on(client, "resolve")
      -- call all, to make sure we hit the expired one
      -- invoke balancer, to expire record and re-query dns
      b:_hit_all()
      assert.spy(client.resolve).was_called_with("mashape.com",nil, nil)
      assert.same(state, copyWheel(b))
    end)

    it("renewed DNS AAAA record; no changes", function()
      local record = dnsAAAA({
        { name = "mashape.com", address = "::1" },
        { name = "mashape.com", address = "::2" },
      })
      dnsA({
        { name = "getkong.org", address = "9.9.9.9" },
      })
      local b = balancer.new({
        hosts = {
          { name = "mashape.com", port = 80, weight = 5 },
          { name = "getkong.org", port = 123, weight = 10 },
        },
        dns = client,
        wheelSize = 100,
      })
      local state = copyWheel(b)
      record.expire = gettime() -1 -- expire current dns cache record
      dnsAAAA({   -- create a new record (identical)
        { name = "mashape.com", address = "::1" },
        { name = "mashape.com", address = "::2" },
      })
      -- create a spy to check whether dns was queried
      spy.on(client, "resolve")
      -- call all, to make sure we hit the expired one
      -- invoke balancer, to expire record and re-query dns
      b:_hit_all()
      assert.spy(client.resolve).was_called_with("mashape.com",nil, nil)
      assert.same(state, copyWheel(b))
    end)
    it("renewed DNS SRV record; no changes", function()
      local record = dnsSRV({
        { name = "gelato.io", target = "1.2.3.6", port = 8001, weight = 5 },
        { name = "gelato.io", target = "1.2.3.6", port = 8002, weight = 5 },
        { name = "gelato.io", target = "1.2.3.6", port = 8003, weight = 5 },
      })
      dnsA({
        { name = "getkong.org", address = "9.9.9.9" },
      })
      local b = balancer.new({
        hosts = {
          { name = "gelato.io" },
          { name = "getkong.org", port = 123, weight = 10 },
        },
        dns = client,
        wheelSize = 100,
      })
      local state = copyWheel(b)
      record.expire = gettime() -1 -- expire current dns cache record
      dnsSRV({    -- create a new record (identical)
        { name = "gelato.io", target = "1.2.3.6", port = 8001, weight = 5 },
        { name = "gelato.io", target = "1.2.3.6", port = 8002, weight = 5 },
        { name = "gelato.io", target = "1.2.3.6", port = 8003, weight = 5 },
      })
      -- create a spy to check whether dns was queried
      spy.on(client, "resolve")
      -- call all, to make sure we hit the expired one
      -- invoke balancer, to expire record and re-query dns
      b:_hit_all()
      assert.spy(client.resolve).was_called_with("gelato.io",nil, nil)
      assert.same(state, copyWheel(b))
    end)
    it("low weight with zero-indices assigned doesn't fail", function()
      -- depending on order of insertion it is either 1 or 0 indices
      -- but it may never error.
      dnsA({
        { name = "mashape.com", address = "1.2.3.4" },
      })
      dnsA({
        { name = "getkong.org", address = "9.9.9.9" },
      })
      balancer.new({
        hosts = {
          { name = "mashape.com", port = 80, weight = 99999 },
          { name = "getkong.org", port = 123, weight = 1 },
        },
        dns = client,
        wheelSize = 1000,
      })
      -- Now the order reversed (weights exchanged)
      dnsA({
        { name = "mashape.com", address = "1.2.3.4" },
      })
      dnsA({
        { name = "getkong.org", address = "9.9.9.9" },
      })
      balancer.new({
        hosts = {
          { name = "mashape.com", port = 80, weight = 1 },
          { name = "getkong.org", port = 123, weight = 99999 },
        },
        dns = client,
        wheelSize = 1000,
      })
    end)
    it("SRV record with 0 weight doesn't fail resolving", function()
      -- depending on order of insertion it is either 1 or 0 indices
      -- but it may never error.
      dnsSRV({
        { name = "gelato.io", target = "1.2.3.6", port = 8001, weight = 0 },
        { name = "gelato.io", target = "1.2.3.6", port = 8002, weight = 0 },
      })
      local b = balancer.new({
        hosts = {
          -- port and weight will be overridden by the above
          { name = "gelato.io", port = 80, weight = 99999 },
        },
        dns = client,
        wheelSize = 100,
      })
      local ip, port = b:getPeer(false, nil, "test")
      assert.equal("1.2.3.6", ip)
      assert(port == 8001 or port == 8002, "port expected 8001 or 8002")
    end)
    it("recreate Kong issue #2131", function()
      -- erasing does not remove the address from the host
      -- so if the same address is added again, and then deleted again
      -- then upon erasing it will find the previous erased address object,
      -- and upon erasing again a nil-referencing issue then occurs
      local ttl = 1
      local record
      local hostname = "dnstest.mashape.com"

      -- mock the resolve/toip methods
      local old_resolve = client.resolve
      local old_toip = client.toip
      finally(function()
          client.resolve = old_resolve
          client.toip = old_toip
        end)
      client.resolve = function(name, ...)
        if name == hostname then
          record = dnsA({
            { name = hostname, address = "1.2.3.4", ttl = ttl },
          })
          return record
        else
          return old_resolve(name, ...)
        end
      end
      client.toip = function(name, ...)
        if name == hostname then
          return "1.2.3.4", ...
        else
          return old_toip(name, ...)
        end
      end

      -- create a new balancer
      local b = balancer.new({
        hosts = {
          { name = hostname, port = 80, weight = 50 },
        },
        dns = client,
        wheelSize = 1000,
        ttl0 = 1,
      })

      sleep(1.1) -- wait for ttl to expire
      -- fetch a peer to reinvoke dns and update balancer, with a ttl=0
      ttl = 0
      b:getPeer(false, nil, "value")   --> force update internal from A to SRV
      sleep(1.1) -- wait for ttl0, as provided to balancer, to expire
      -- restore ttl to non-0, and fetch a peer to update balancer
      ttl = 1
      b:getPeer(false, nil, "value")   --> force update internal from SRV to A
      sleep(1.1) -- wait for ttl to expire
      -- fetch a peer to reinvoke dns and update balancer, with a ttl=0
      ttl = 0
      b:getPeer(false, nil, "value")   --> force update internal from A to SRV
    end)
  end)
end)
