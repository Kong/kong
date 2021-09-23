
local client -- forward declaration
local helpers = require "spec.test_helpers"
local dnsSRV = function(...) return helpers.dnsSRV(client, ...) end
local dnsA = function(...) return helpers.dnsA(client, ...) end
local dnsExpire = helpers.dnsExpire


for algorithm, balancer_module in helpers.balancer_types() do

  describe("[" .. algorithm .. "]", function()

    local snapshot

    setup(function()
      _G.package.loaded["resty.dns.client"] = nil -- make sure module is reloaded
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
      assert:set_parameter("TableFormatLevel", 10)
      collectgarbage()
      collectgarbage()
    end)


    after_each(function()
      snapshot:revert()  -- undo any spying/stubbing etc.
      collectgarbage()
      collectgarbage()
    end)


    describe("health:", function()

      local b

      before_each(function()
        b = balancer_module.new({
          dns = client,
          healthThreshold = 50,
        })
      end)

      after_each(function()
        b = nil
      end)

      it("empty balancer is unhealthy", function()
        assert.is_false((b:getStatus().healthy))
      end)

      it("adding first address marks healthy", function()
        assert.is_false(b:getStatus().healthy)
        b:addHost("127.0.0.1", 8000, 100)
        assert.is_true(b:getStatus().healthy)
      end)

      it("removing last address marks unhealthy", function()
        assert.is_false(b:getStatus().healthy)
        b:addHost("127.0.0.1", 8000, 100)
        assert.is_true(b:getStatus().healthy)
        b:removeHost("127.0.0.1", 8000)
        assert.is_false(b:getStatus().healthy)
      end)

      it("dropping below the health threshold marks unhealthy", function()
        assert.is_false(b:getStatus().healthy)
        b:addHost("127.0.0.1", 8000, 100)
        b:addHost("127.0.0.2", 8000, 100)
        b:addHost("127.0.0.3", 8000, 100)
        assert.is_true(b:getStatus().healthy)
        b:setAddressStatus(false, "127.0.0.2", 8000)
        assert.is_true(b:getStatus().healthy)
        b:setAddressStatus(false, "127.0.0.3", 8000)
        assert.is_false(b:getStatus().healthy)
      end)

      it("rising above the health threshold marks healthy", function()
        assert.is_false(b:getStatus().healthy)
        b:addHost("127.0.0.1", 8000, 100)
        b:addHost("127.0.0.2", 8000, 100)
        b:addHost("127.0.0.3", 8000, 100)
        b:setAddressStatus(false, "127.0.0.2", 8000)
        b:setAddressStatus(false, "127.0.0.3", 8000)
        assert.is_false(b:getStatus().healthy)
        b:setAddressStatus(true, "127.0.0.2", 8000)
        assert.is_true(b:getStatus().healthy)
      end)

    end)



    describe("weights:", function()

      local b

      before_each(function()
        b = balancer_module.new({
          dns = client,
        })
        b.getPeer = function(self)
          -- we do not really need to get a peer, just touch all addresses to
          -- potentially force DNS renewals
          for i, addr in ipairs(self.addresses) do
            if algorithm == "consistent-hashing" then
              addr:getPeer(nil, nil, tostring(i))
            else
              addr:getPeer()
            end
          end
        end
        b:addHost("127.0.0.1", 8000, 100)  -- add 1 initial host
      end)

      after_each(function()
        b = nil
      end)



      describe("(A)", function()

        it("adding a host",function()
          dnsA({
            { name = "arecord.tst", address = "1.2.3.4" },
            { name = "arecord.tst", address = "5.6.7.8" },
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

          b:addHost("arecord.tst", 8001, 25)
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
                host = "arecord.tst",
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

        it("removing a host",function()
          dnsA({
            { name = "arecord.tst", address = "1.2.3.4" },
            { name = "arecord.tst", address = "5.6.7.8" },
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

          b:addHost("arecord.tst", 8001, 25)
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
                host = "arecord.tst",
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

          b:removeHost("arecord.tst", 8001, 25)
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

        end)

        it("switching address availability",function()
          dnsA({
            { name = "arecord.tst", address = "1.2.3.4" },
            { name = "arecord.tst", address = "5.6.7.8" },
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

          b:addHost("arecord.tst", 8001, 25)
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
                host = "arecord.tst",
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
          assert(b:setAddressStatus(false, "1.2.3.4", 8001, "arecord.tst"))
          b:addHost("arecord.tst", 8001, 25)
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
                host = "arecord.tst",
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
          assert(b:setAddressStatus(true, "1.2.3.4", 8001, "arecord.tst"))
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
                host = "arecord.tst",
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
            { name = "arecord.tst", address = "1.2.3.4" },
            { name = "arecord.tst", address = "5.6.7.8" },
          })

          b:addHost("arecord.tst", 8001, 25)
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
                host = "arecord.tst",
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

          b:addHost("arecord.tst", 8001, 50) -- adding again changes weight
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
                host = "arecord.tst",
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
            { name = "arecord.tst", address = "1.2.3.4" },
            { name = "arecord.tst", address = "5.6.7.8" },
          })

          b:addHost("arecord.tst", 8001, 25)
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
                host = "arecord.tst",
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
          assert(b:setAddressStatus(false, "1.2.3.4", 8001, "arecord.tst"))
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
                host = "arecord.tst",
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

          b:addHost("arecord.tst", 8001, 50) -- adding again changes weight
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
                host = "arecord.tst",
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
            { name = "srvrecord.tst", target = "1.1.1.1", port = 9000, weight = 10 },
            { name = "srvrecord.tst", target = "2.2.2.2", port = 9001, weight = 10 },
          })

          b:addHost("srvrecord.tst", 8001, 25)
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
                host = "srvrecord.tst",
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

        it("removing a host",function()
          dnsSRV({
            { name = "srvrecord.tst", target = "1.1.1.1", port = 9000, weight = 10 },
            { name = "srvrecord.tst", target = "2.2.2.2", port = 9001, weight = 10 },
          })

          b:addHost("srvrecord.tst", 8001, 25)
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
                host = "srvrecord.tst",
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

          b:removeHost("srvrecord.tst", 8001, 25)
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
        end)

        it("switching address availability",function()
          dnsSRV({
            { name = "srvrecord.tst", target = "1.1.1.1", port = 9000, weight = 10 },
            { name = "srvrecord.tst", target = "2.2.2.2", port = 9001, weight = 10 },
          })

          b:addHost("srvrecord.tst", 8001, 25)
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
                host = "srvrecord.tst",
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
          assert(b:setAddressStatus(false, "1.1.1.1", 9000, "srvrecord.tst"))
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
                host = "srvrecord.tst",
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
          assert(b:setAddressStatus(true, "1.1.1.1", 9000, "srvrecord.tst"))
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
                host = "srvrecord.tst",
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
            { name = "srvrecord.tst", target = "1.1.1.1", port = 9000, weight = 10 },
            { name = "srvrecord.tst", target = "2.2.2.2", port = 9001, weight = 10 },
          })

          b:addHost("srvrecord.tst", 8001, 10)
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
                host = "srvrecord.tst",
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
            { name = "srvrecord.tst", target = "1.1.1.1", port = 9000, weight = 20 },
            { name = "srvrecord.tst", target = "2.2.2.2", port = 9001, weight = 20 },
          })
          b:getPeer()  -- touch all adresses to force dns renewal
          b:addHost("srvrecord.tst", 8001, 99) -- add again to update nodeWeight

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
                host = "srvrecord.tst",
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
            { name = "srvrecord.tst", target = "1.1.1.1", port = 9000, weight = 10 },
            { name = "srvrecord.tst", target = "2.2.2.2", port = 9001, weight = 10 },
          })

          b:addHost("srvrecord.tst", 8001, 25)
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
                host = "srvrecord.tst",
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
          assert(b:setAddressStatus(false, "2.2.2.2", 9001, "srvrecord.tst"))
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
                host = "srvrecord.tst",
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
            { name = "srvrecord.tst", target = "1.1.1.1", port = 9000, weight = 20 },
            { name = "srvrecord.tst", target = "2.2.2.2", port = 9001, weight = 20 },
          })
          -- touch all adresses to force dns renewal
          if algorithm == "consistent-hashing" then
            b:getPeer(nil, nil, "value")
          else
            b:getPeer()
          end
          b:addHost("srvrecord.tst", 8001, 99) -- add again to update nodeWeight

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
                host = "srvrecord.tst",
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



    describe("getpeer()", function()

      local b

      before_each(function()
        b = balancer_module.new({
          dns = client,
          healthThreshold = 50,
          useSRVname = false,
        })
      end)

      after_each(function()
        b = nil
      end)


      it("returns expected results/types when using SRV with IP", function()
        dnsSRV({
          { name = "konghq.com", target = "1.1.1.1", port = 2, weight = 3 },
        })
        b:addHost("konghq.com", 8000, 50)
        local ip, port, hostname, handle
        if algorithm == "consistent-hashing" then
          ip, port, hostname, handle = b:getPeer(false, nil, "a string")
        else
          ip, port, hostname, handle = b:getPeer()
        end
        assert.equal("1.1.1.1", ip)
        assert.equal(2, port)
        assert.equal("konghq.com", hostname)
        assert.equal("userdata", type(handle.__udata))
      end)


      it("returns expected results/types when using SRV with name ('useSRVname=false')", function()
        dnsA({
          { name = "getkong.org", address = "1.2.3.4" },
        })
        dnsSRV({
          { name = "konghq.com", target = "getkong.org", port = 2, weight = 3 },
        })
        b:addHost("konghq.com", 8000, 50)
        local ip, port, hostname, handle
        if algorithm == "consistent-hashing" then
          ip, port, hostname, handle = b:getPeer(false, nil, "a string")
        else
          ip, port, hostname, handle = b:getPeer()
        end
        assert.equal("1.2.3.4", ip)
        assert.equal(2, port)
        assert.equal("konghq.com", hostname)
        assert.equal("userdata", type(handle.__udata))
      end)


      it("returns expected results/types when using SRV with name ('useSRVname=true')", function()
        b.useSRVname = true -- override setting specified when creating

        dnsA({
          { name = "getkong.org", address = "1.2.3.4" },
        })
        dnsSRV({
          { name = "konghq.com", target = "getkong.org", port = 2, weight = 3 },
        })
        b:addHost("konghq.com", 8000, 50)
        local ip, port, hostname, handle
        if algorithm == "consistent-hashing" then
          ip, port, hostname, handle = b:getPeer(false, nil, "a string")
        else
          ip, port, hostname, handle = b:getPeer()
        end
        assert.equal("1.2.3.4", ip)
        assert.equal(2, port)
        assert.equal("getkong.org", hostname)
        assert.equal("userdata", type(handle.__udata))
      end)


      it("returns expected results/types when using A", function()
        dnsA({
          { name = "getkong.org", address = "1.2.3.4" },
        })
        b:addHost("getkong.org", 8000, 50)
        local ip, port, hostname, handle
        if algorithm == "consistent-hashing" then
          ip, port, hostname, handle = b:getPeer(false, nil, "another string")
        else
          ip, port, hostname, handle = b:getPeer()
        end
        assert.equal("1.2.3.4", ip)
        assert.equal(8000, port)
        assert.equal("getkong.org", hostname)
        assert.equal("userdata", type(handle.__udata))
      end)


      it("returns expected results/types when using IPv4", function()
        b:addHost("4.3.2.1", 8000, 50)
        local ip, port, hostname, handle
        if algorithm == "consistent-hashing" then
          ip, port, hostname, handle = b:getPeer(false, nil, "a string")
        else
          ip, port, hostname, handle = b:getPeer()
        end
        assert.equal("4.3.2.1", ip)
        assert.equal(8000, port)
        assert.equal(nil, hostname)
        assert.equal("userdata", type(handle.__udata))
      end)


      it("returns expected results/types when using IPv6", function()
        b:addHost("::1", 8000, 50)
        local ip, port, hostname, handle
        if algorithm == "consistent-hashing" then
          ip, port, hostname, handle = b:getPeer(false, nil, "just a string")
        else
          ip, port, hostname, handle = b:getPeer()
        end
        assert.equal("[::1]", ip)
        assert.equal(8000, port)
        assert.equal(nil, hostname)
        assert.equal("userdata", type(handle.__udata))
      end)


      it("fails when there are no addresses added", function()
        local ip, port, hostname, handle
        if algorithm == "consistent-hashing" then
          ip, port, hostname, handle = b:getPeer(false, nil, "any string")
        else
          ip, port, hostname, handle = b:getPeer()
        end
        assert.same({
            nil, "Balancer is unhealthy", nil, nil,
          }, {
            ip, port, hostname, handle
          }
        )
      end)


      it("fails when all addresses are unhealthy", function()
        b:addHost("127.0.0.1", 8000, 100)
        b:addHost("127.0.0.2", 8000, 100)
        b:addHost("127.0.0.3", 8000, 100)
        b:setAddressStatus(false, "127.0.0.1", 8000)
        b:setAddressStatus(false, "127.0.0.2", 8000)
        b:setAddressStatus(false, "127.0.0.3", 8000)
        local ip, port, hostname, handle
        if algorithm == "consistent-hashing" then
          ip, port, hostname, handle = b:getPeer(false, nil, "a client string")
        else
          ip, port, hostname, handle = b:getPeer()
        end
        assert.same({
            nil, "Balancer is unhealthy", nil, nil,
          }, {
            ip, port, hostname, handle
          }
        )
      end)


      it("fails when balancer switches to unhealthy", function()
        b:addHost("127.0.0.1", 8000, 100)
        b:addHost("127.0.0.2", 8000, 100)
        b:addHost("127.0.0.3", 8000, 100)
        if algorithm == "consistent-hashing" then
          assert.not_nil(b:getPeer(false, nil, "any client string here"))
        else
          assert.not_nil(b:getPeer())
        end

        b:setAddressStatus(false, "127.0.0.1", 8000)
        b:setAddressStatus(false, "127.0.0.2", 8000)
        local ip, port, hostname, handle
        if algorithm == "consistent-hashing" then
          ip, port, hostname, handle = b:getPeer(false, nil, "any string here")
        else
          ip, port, hostname, handle = b:getPeer()
        end
        assert.same({
            nil, "Balancer is unhealthy", nil, nil,
          }, {
            ip, port, hostname, handle
          }
        )
      end)


      it("recovers when balancer switches to healthy", function()
        b:addHost("127.0.0.1", 8000, 100)
        b:addHost("127.0.0.2", 8000, 100)
        b:addHost("127.0.0.3", 8000, 100)
        if algorithm == "consistent-hashing" then
          assert.not_nil(b:getPeer(false, nil, "string from the client"))
        else
          assert.not_nil(b:getPeer())
        end

        b:setAddressStatus(false, "127.0.0.1", 8000)
        b:setAddressStatus(false, "127.0.0.2", 8000)
        local ip, port, hostname, handle
        if algorithm == "consistent-hashing" then
          ip, port, hostname, handle = b:getPeer(false, nil, "string from the client")
        else
          ip, port, hostname, handle = b:getPeer()
        end
        assert.same({
            nil, "Balancer is unhealthy", nil, nil,
          }, {
            ip, port, hostname, handle
          }
        )

        b:setAddressStatus(true, "127.0.0.2", 8000)
        if algorithm == "consistent-hashing" then
          assert.not_nil(b:getPeer(false, nil, "a string"))
        else
          assert.not_nil(b:getPeer())
        end
      end)


      it("recovers when dns entries are replaced by healthy ones", function()
        dnsA({
          { name = "getkong.org", address = "1.2.3.4", ttl = 2 },
        })
        b:addHost("getkong.org", 8000, 50)
        if algorithm == "consistent-hashing" then
          assert.not_nil(b:getPeer(false, nil, "from the client"))
        else
          assert.not_nil(b:getPeer())
        end

        -- mark it as unhealthy
        assert(b:setAddressStatus(false, "1.2.3.4", 8000, "getkong.org"))
        local ip, port, hostname, handle
        if algorithm == "consistent-hashing" then
          ip, port, hostname, handle = b:getPeer(false, nil, "from the client")
        else
          ip, port, hostname, handle = b:getPeer()
        end
        assert.same({
            nil, "Balancer is unhealthy", nil, nil,
          }, {
            ip, port, hostname, handle,
          }
        )

        -- update DNS with a new backend IP
        -- balancer should now recover since a new healthy backend is available
        dnsA({
          { name = "getkong.org", address = "5.6.7.8", ttl = 60 },
        })

        local timeout = ngx.now() + 5   -- we'll try for 5 seconds
        while true do
          assert(ngx.now() < timeout, "timeout")
          local ip
          if algorithm == "consistent-hashing" then
            ip = b:getPeer(false, nil, "from the client")
            if ip ~= nil then
              break  -- expected result, success!
            end
          else
            ip = b:getPeer()
            if ip == "5.6.7.8" then
              break  -- expected result, success!
            end
          end

          ngx.sleep(0.1)  -- wait a bit before retrying
        end

      end)

    end)



    describe("status:", function()

      local b

      before_each(function()
        b = balancer_module.new({
          dns = client,
        })
      end)

      after_each(function()
        b = nil
      end)



      describe("reports DNS source", function()

        it("status report",function()
          b:addHost("127.0.0.1", 8000, 100)
          b:addHost("0::1", 8080, 50)
          dnsSRV({
            { name = "srvrecord.tst", target = "1.1.1.1", port = 9000, weight = 10 },
            { name = "srvrecord.tst", target = "2.2.2.2", port = 9001, weight = 10 },
          })
          b:addHost("srvrecord.tst", 1234, 9999)
          dnsA({
            { name = "getkong.org", address = "5.6.7.8", ttl = 0 },
          })
          b:addHost("getkong.org", 5678, 1000)
          b:addHost("notachanceinhell.this.name.exists.konghq.com", 4321, 100)

          if algorithm == "consistent-hashing" then
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
                  host = "getkong.org",
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
                      ip = "getkong.org",
                      port = 5678,
                      weight = 1000
                    },
                  },
                },
                {
                  host = "notachanceinhell.this.name.exists.konghq.com",
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
                  host = "srvrecord.tst",
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
            }, b:getStatus())
          else
            assert.same({
              healthy = true,
              weight = {
                total = 1170,
                available = 1170,
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
                  host = "srvrecord.tst",
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
                {
                  host = "getkong.org",
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
                      ip = "getkong.org",
                      port = 5678,
                      weight = 1000
                    },
                  },
                },
                {
                  host = "notachanceinhell.this.name.exists.konghq.com",
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

              },
            }, b:getStatus())
          end
        end)

      end)

    end)



    describe("GC:", function()

      it("removed Hosts get collected",function()
        local b = balancer_module.new({
          dns = client,
        })
        b:addHost("127.0.0.1", 8000, 100)

        local test_table = setmetatable({}, { __mode = "v" })
        test_table.key = b.hosts[1]
        assert.not_nil(next(test_table))

        -- destroy it
        b:removeHost("127.0.0.1", 8000)
        collectgarbage()
        collectgarbage()
        assert.is_nil(next(test_table))
      end)


      it("dropped balancers get collected",function()
        local b = balancer_module.new({
          dns = client,
        })
        b:addHost("127.0.0.1", 8000, 100)

        local test_table = setmetatable({}, { __mode = "v" })
        test_table.key = b
        assert.not_nil(next(test_table))

        -- destroy it
        ngx.sleep(0)  -- without this it fails, why, why, why?
        b = nil       -- luacheck: ignore

        collectgarbage()
        collectgarbage()
        --assert.is_nil(next(test_table))  -- doesn't work, hangs if failed, luassert bug
        assert.is_nil(test_table.key)
        assert.equal("nil", tostring(test_table.key))
      end)

    end)

  end)

end
