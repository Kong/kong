

local client, lcb

local helpers = require "spec.test_helpers"
--local gettime = helpers.gettime
--local sleep = helpers.sleep
local dnsSRV = function(...) return helpers.dnsSRV(client, ...) end
local dnsA = function(...) return helpers.dnsA(client, ...) end
--local dnsAAAA = function(...) return helpers.dnsAAAA(client, ...) end
--local dnsExpire = helpers.dnsExpire
local t_insert = table.insert


local validate_lcb
do
  -- format string to fixed length for table-like display
  local function size(str, l)
    local isnum = type(str) == "number"
    str = tostring(str)
    str = str:sub(1, l)
    if isnum then
      str = string.rep(" ", l - #str) .. str
    else
      str = str .. string.rep(" ", l - #str)
    end
    return str
  end

  function validate_lcb(b, debug)
    local available, unavailable = 0, 0
    if debug then
      print("host.hostname   addr.ip        weight count   sort-order")
    end
    for i, addr in ipairs(b.addresses) do
      local display = {}
      t_insert(display, size(addr.host.hostname, 15))
      t_insert(display, size(addr.ip, 15))
      t_insert(display, size(addr.weight, 5))
      t_insert(display, size(addr.connectionCount, 5))
      if b.binaryHeap:valueByPayload(addr) then
        t_insert(display, size(("%.10f"):format(b.binaryHeap:valueByPayload(addr)), 14))
      else
        t_insert(display, size(b.binaryHeap:valueByPayload(addr), 14))
      end
      if b.binaryHeap:valueByPayload(addr) then
        -- it's in the heap
        assert(not addr.disabled, "should be enabled when in the heap")
        assert(addr.available, "should be available when in the heap")
        available = available + 1
        assert(b.binaryHeap:valueByPayload(addr) == (addr.connectionCount+1)/addr.weight)
      else
        assert(not addr.disabled, "should be enabled when not in the heap")
        assert(not addr.available, "should not be available when not in the heap")
        unavailable = unavailable + 1
      end
      if debug then
        print(table.concat(display, " "))
      end
    end
    assert(available + unavailable == #b.addresses, "mismatch in counts")
    return b
  end
end


describe("[least-connections]", function()

  local snapshot

  setup(function()
    _G.package.loaded["resty.dns.client"] = nil -- make sure module is reloaded
    lcb = require "resty.dns.balancer.least_connections"
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
      local b = validate_lcb(lcb.new({
        dns = client,
        hosts = {
          "konghq.com",                                      -- name only, as string
          { name = "github.com" },                           -- name only, as table
          { name = "getkong.org", port = 80, weight = 25 },  -- fully specified, as table
        },
      }))
      assert.equal("konghq.com", b.addresses[1].host.hostname)
      assert.equal("github.com", b.addresses[2].host.hostname)
      assert.equal("getkong.org", b.addresses[3].host.hostname)
    end)
  end)


  describe("getPeer()", function()

    it("honours weights", function()
      dnsSRV({
        { name = "konghq.com", target = "20.20.20.20", port = 80, weight = 20 },
        { name = "konghq.com", target = "50.50.50.50", port = 80, weight = 50 },
      })
      local b = validate_lcb(lcb.new({
        dns = client,
        hosts = { "konghq.com" },
      }))

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
        { name = "konghq.com", target = "20.20.20.20", port = 80, weight = 20 },
        { name = "konghq.com", target = "50.50.50.50", port = 80, weight = 50 },
      })
      local b = validate_lcb(lcb.new({
        dns = client,
        hosts = { "konghq.com" },
      }))

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
        { name = "konghq.com", target = "20.20.20.20", port = 80, weight = 20 },
        { name = "konghq.com", target = "50.50.50.50", port = 80, weight = 50 },
      })
      local b = validate_lcb(lcb.new({
        dns = client,
        hosts = { "konghq.com" },
      }))

      -- mark one as unavailable
      b:setAddressStatus(false, "50.50.50.50", 80, "konghq.com")
      local counts = {}
      local handles = {}
      for i = 1,70 do
        local ip, _, _, handle = b:getPeer()
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
        { name = "konghq.com", target = "20.20.20.20", port = 80, weight = 20 },
        { name = "konghq.com", target = "50.50.50.50", port = 80, weight = 50 },
      })
      local b = validate_lcb(lcb.new({
        dns = client,
        hosts = { "konghq.com" },
      }))

      -- mark one as unavailable
      b:setAddressStatus(false, "20.20.20.20", 80, "konghq.com")
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
      b:setAddressStatus(true, "20.20.20.20", 80, "konghq.com")
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
        { name = "konghq.com", target = "20.20.20.20", port = 80, weight = 20 },
        { name = "konghq.com", target = "50.50.50.50", port = 80, weight = 50 },
        { name = "konghq.com", target = "70.70.70.70", port = 80, weight = 70 },
      })
      local b = validate_lcb(lcb.new({
        dns = client,
        hosts = { "konghq.com" },
      }))

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
        { name = "konghq.com", target = "20.20.20.20", port = 80, weight = 20 },
        { name = "konghq.com", target = "50.50.50.50", port = 80, weight = 50 },
        { name = "konghq.com", target = "70.70.70.70", port = 80, weight = 70 },
      })
      local b = validate_lcb(lcb.new({
        dns = client,
        hosts = { "konghq.com" },
      }))

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
        { name = "konghq.com", target = "20.20.20.20", port = 80, weight = 20 },
        { name = "konghq.com", target = "50.50.50.50", port = 80, weight = 50 },
      })
      local b = validate_lcb(lcb.new({
        dns = client,
        hosts = { "konghq.com" },
      }))

      local counts = {}
      local handle -- define outside loop, so it gets reused and released
      for i = 1,70 do
        local ip, _
        ip, _, _, handle = b:getPeer(nil, handle)
        counts[ip] = (counts[ip] or 0) + 1
      end

      validate_lcb(b)

      local ccount = 0
      for i, addr in ipairs(b.addresses) do
        ccount = ccount + addr.connectionCount
      end
      assert.equal(1, ccount)
    end)

  end)


  describe("release()", function()

    it("releases a connection", function()
      dnsSRV({
        { name = "konghq.com", target = "20.20.20.20", port = 80, weight = 20 },
      })
      local b = validate_lcb(lcb.new({
        dns = client,
        hosts = { "konghq.com" },
      }))

      local ip, _, _, handle = b:getPeer()
      assert.equal("20.20.20.20", ip)
      assert.equal(1, b.addresses[1].connectionCount)

      handle:release()
      assert.equal(0, b.addresses[1].connectionCount)
    end)


    it("releases connection of already disabled/removed address", function()
      dnsSRV({
        { name = "konghq.com", target = "20.20.20.20", port = 80, weight = 20 },
      })
      local b = validate_lcb(lcb.new({
        dns = client,
        hosts = { "konghq.com" },
      }))

      local ip, _, _, handle = b:getPeer()
      assert.equal("20.20.20.20", ip)
      assert.equal(1, b.addresses[1].connectionCount)

      -- remove the host and its addresses
      b:removeHost("konghq.com")
      assert.equal(0, #b.addresses)

      local addr = handle.address
      handle:release()
      assert.equal(0, addr.connectionCount)
    end)

  end)


  describe("garbage collection:", function()

    it("releases a connection when a handle is collected", function()
      dnsSRV({
        { name = "konghq.com", target = "20.20.20.20", port = 80, weight = 20 },
      })
      local b = validate_lcb(lcb.new({
        dns = client,
        hosts = { "konghq.com" },
      }))

      local ip, _, _, handle = b:getPeer()
      assert.equal("20.20.20.20", ip)
      assert.equal(1, b.addresses[1].connectionCount)

      local addr = handle.address
      handle = nil  --luacheck: ignore
      collectgarbage()
      collectgarbage()

      assert.equal(0, addr.connectionCount)
    end)


    it("releases connection of already disabled/removed address", function()
      dnsSRV({
        { name = "konghq.com", target = "20.20.20.20", port = 80, weight = 20 },
      })
      local b = validate_lcb(lcb.new({
        dns = client,
        hosts = { "konghq.com" },
      }))

      local ip, _, _, handle = b:getPeer()
      assert.equal("20.20.20.20", ip)
      assert.equal(1, b.addresses[1].connectionCount)

      -- remove the host and its addresses
      b:removeHost("konghq.com")
      assert.equal(0, #b.addresses)

      local addr = handle.address
      handle = nil  --luacheck: ignore
      collectgarbage()
      collectgarbage()

      assert.equal(0, addr.connectionCount)
    end)

  end)

end)
