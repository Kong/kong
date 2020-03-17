local cjson = require "cjson"
local helpers = require "spec.helpers"

-- returns nth byte (0: LSB, 3: MSB if 32-bit)
local function nbyt(x, n)
  return bit.band(bit.rshift(x, 8*n), 0xff)
end

local function be_bytes(x)
  return nbyt(x, 3), nbyt(x, 2), nbyt(x, 1), nbyt(x, 0)
end

for _, strategy in helpers.each_strategy() do

  describe("gRPC-Gateway [#" .. strategy .. "]", function()
    local proxy_client
    local proxy_client_ssl


    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
      }, {
        "grpc-gateway",
      })

      local service1 = assert(bp.services:insert {
        name = "grpc",
        url = "grpc://localhost:15002",
      })

      local route1 = assert(bp.routes:insert {
        protocols = { "http", "https" },
        paths = { "/" },
        service = service1,
      })

      assert(bp.plugins:insert {
        route = route1,
        name = "grpc-gateway",
        config = {
          proto = "spec/fixtures/grpc/hello_gw.proto",
        },
      })

      assert(helpers.start_kong {
        database = strategy,
        plugins = "bundled,grpc-gateway",
      })
    end)

    before_each(function()
      proxy_client = helpers.proxy_client(1000)
      proxy_client_ssl = helpers.proxy_ssl_client(1000)
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    test("main entrypoint", function()
      local res, err = proxy_client:get("/v1/messages/john_doe")
      local data = cjson.decode((res:read_body()))

      assert.equal(200, res.status)
      assert.is_nil(err)

      assert.same({reply = "hello john_doe"}, data)
    end)

    test("additional binding", function()
      local res, err = proxy_client:get("/v1/messages/legacy/john_doe")
      local data = cjson.decode((res:read_body()))

      assert.equal(200, res.status)
      assert.is_nil(err)

      assert.same({reply = "hello john_doe"}, data)
    end)

    test("unknown path", function()
      local res, err = proxy_client:get("/v1/messages/john_doe/bai")
      assert.not_equal(200, res.status)
      assert.equal("Bad Request", res.reason)
    end)

 end)
end
