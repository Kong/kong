local cjson = require "cjson"
local helpers = require "spec.helpers"

for _, strategy in helpers.each_strategy() do

  describe("gRPC-Gateway [#" .. strategy .. "]", function()
    local proxy_client


    lazy_setup(function()
      assert(helpers.start_grpc_target())

      -- start_grpc_target takes long time, the db socket might already
      -- be timeout, so we close it to avoid `db:init_connector` failing
      -- in `helpers.get_db_utils`
      helpers.db:connect()
      helpers.db:close()

      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
      }, {
        "grpc-gateway",
      })

      -- the sample server we used is from
      -- https://github.com/grpc/grpc-go/tree/master/examples/features/reflection
      -- which listens 50051 by default
      local service1 = assert(bp.services:insert {
        name = "grpc",
        protocol = "grpc",
        host = "127.0.0.1",
        port = helpers.get_grpc_target_port(),
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
          proto = "./spec/fixtures/grpc/targetservice.proto",
        },
      })

      assert(helpers.start_kong {
        database = strategy,
        plugins = "bundled,grpc-gateway",
      })
    end)

    before_each(function()
      proxy_client = helpers.proxy_client(1000)
    end)

    lazy_teardown(function()
      helpers.stop_kong()
      helpers.stop_grpc_target()
    end)

    test("main entrypoint", function()
      local res, err = proxy_client:get("/v1/messages/john_doe")

      assert.equal(200, res.status)
      assert.is_nil(err)

      local body = res:read_body()
      local data = cjson.decode(body)

      assert.same({reply = "hello john_doe", boolean_test = false}, data)
    end)

    test("additional binding", function()
      local res, err = proxy_client:get("/v1/messages/legacy/john_doe")

      assert.equal(200, res.status)
      assert.is_nil(err)

      local data = cjson.decode((res:read_body()))

      assert.same({reply = "hello john_doe", boolean_test = false}, data)
    end)

    test("removes unbound query args", function()
      local res, err = proxy_client:get("/v1/messages/john_doe?arg1=1&arg2.test=2")

      assert.equal(200, res.status)
      assert.is_nil(err)

      local body = res:read_body()
      local data = cjson.decode(body)

      assert.same({reply = "hello john_doe", boolean_test = false}, data)
    end)

    describe("boolean behavior", function ()
      test("true", function()
        local res, err = proxy_client:get("/v1/messages/legacy/john_doe?boolean_test=true")
        assert.equal(200, res.status)
        assert.is_nil(err)

        local body = res:read_body()
        local data = cjson.decode(body)
        assert.same({reply = "hello john_doe", boolean_test = true}, data)
      end)

      test("false", function()
        local res, err = proxy_client:get("/v1/messages/legacy/john_doe?boolean_test=false")

        assert.equal(200, res.status)
        assert.is_nil(err)

        local body = res:read_body()
        local data = cjson.decode(body)

        assert.same({reply = "hello john_doe", boolean_test = false}, data)
      end)

      test("zero", function()
        local res, err = proxy_client:get("/v1/messages/legacy/john_doe?boolean_test=0")

        assert.equal(200, res.status)
        assert.is_nil(err)

        local body = res:read_body()
        local data = cjson.decode(body)

        assert.same({reply = "hello john_doe", boolean_test = false}, data)
      end)

      test("non-zero", function()
        local res, err = proxy_client:get("/v1/messages/legacy/john_doe?boolean_test=1")
        assert.equal(200, res.status)
        assert.is_nil(err)

        local body = res:read_body()
        local data = cjson.decode(body)

        assert.same({reply = "hello john_doe", boolean_test = true}, data)
      end)
    end)

    test("unknown path", function()
      local res, _ = proxy_client:get("/v1/messages/john_doe/bai")
      assert.equal(400, res.status)
      assert.equal("Bad Request", res.reason)
    end)

    test("transforms grpc-status to HTTP status code", function()
      local res, _ = proxy_client:get("/v1/unknown/john_doe")
      -- per ttps://github.com/googleapis/googleapis/blob/master/google/rpc/code.proto
      -- grpc-status: 12: UNIMPLEMENTED are mapped to http code 500
      assert.equal(500, res.status)
      assert.equal('12', res.headers['grpc-status'])
    end)

    describe("known types transformations", function()

      test("Timestamp", function()
        local now = os.time()
        local now_8601 = os.date("!%FT%T", now)
        local ago_8601 = os.date("!%FT%TZ", now - 315)

        local res, _ = proxy_client:post("/bounce", {
          headers = { ["Content-Type"] = "application/json" },
          body = { message = "hi", when = ago_8601, now = now_8601 },
        })
        assert.equal(200, res.status)

        local body = res:read_body()
        assert.same({
          now = now_8601,
          reply = "hello hi",
          time_message = ago_8601 .. " was 5m15s ago",
        }, cjson.decode(body))
      end)
    end)

    test("structured URI args", function()
      local res, _ = proxy_client:get("/v1/grow/tail", {
        query = {
          name = "lizard",
          hands = { count = 0, endings = "fingers" },
          legs = { count = 4, endings = "toes" },
          tail = {count = 0, endings = "tip" },
        }
      })
      assert.equal(200, res.status)
      local body = assert(res:read_body())
      assert.same({
        name = "lizard",
        hands = { count = 0, endings = "fingers" },
        legs = { count = 4, endings = "toes" },
        tail = {count = 1, endings = "tip" },
      }, cjson.decode(body))
    end)

    test("null in json", function()
      local res, _ = proxy_client:post("/bounce", {
        headers = { ["Content-Type"] = "application/json" },
        body = { message = cjson.null },
      })
      assert.equal(400, res.status)
    end)

    describe("regression", function()
      test("empty array in json #10801", function()
        local req_body = { array = {}, nullable = "ahaha" }
        local res, _ = proxy_client:post("/v1/echo", {
          headers = { ["Content-Type"] = "application/json" },
          body = req_body,
        })
        assert.equal(200, res.status)
  
        local body = res:read_body()
        assert.same(req_body, cjson.decode(body))
        -- it should be encoded as empty array in json instead of `null` or `{}`
        assert.matches("[]", body, nil, true)
      end)
  
      -- Bug found when test FTI-5002's fix. It will be fixed in another PR.
      test("empty message #10802", function()
        local req_body = { array = {}, nullable = "" }
        local res, _ = proxy_client:post("/v1/echo", {
          headers = { ["Content-Type"] = "application/json" },
          body = req_body,
        })
        assert.equal(200, res.status)
  
        local body = res:read_body()
        assert.same(req_body, cjson.decode(body))
        -- it should be encoded as empty array in json instead of `null` or `{}`
        assert.matches("[]", body, nil, true)
      end)
    end)
  end)
end
