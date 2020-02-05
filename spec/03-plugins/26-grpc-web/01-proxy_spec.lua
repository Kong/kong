local helpers = require "spec.helpers"

for _, strategy in helpers.each_strategy() do

  describe("gRPC-Web Proxying [#" .. strategy .. "]", function()
    local proxy_client
    local proxy_client_ssl

    local HELLO_REQUEST_BODY = "AAAAAAYKBGhleWE="

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
      }, {
        "grpc-web",
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
        name = "grpc-web",
      })

      assert(helpers.start_kong {
        database = strategy,
        plugins = "bundled,grpc-web",
      })

      proxy_client = helpers.proxy_client()
      proxy_client_ssl = helpers.proxy_ssl_client()
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    test("Call gRCP via HTTP", function()
      local res, err = proxy_client:post("/hello.HelloService/SayHello", {
        headers = {
          ["Content-Type"] = "application/grpc-web-text",
          ["Content-Length"] = tostring(#HELLO_REQUEST_BODY),
        },
        body = HELLO_REQUEST_BODY,
      })

      assert.equal(
        "AAAAAAwKCmhlbGxvIGhleWE=gAAAAB5ncnBjLXN0YXR1czowDQpncnBjLW1lc3NhZ2U6DQo=",
        res:read_body())
      assert.is_nil(err)
    end)

    test("Call gRCP via HTTPS", function()
      local res, err = proxy_client_ssl:post("/hello.HelloService/SayHello", {
        headers = {
          ["Content-Type"] = "application/grpc-web-text",
          ["Content-Length"] = tostring(#HELLO_REQUEST_BODY),
        },
        body = HELLO_REQUEST_BODY,
      })

      assert.equal(
        "AAAAAAwKCmhlbGxvIGhleWE=gAAAAB5ncnBjLXN0YXR1czowDQpncnBjLW1lc3NhZ2U6DQo=",
        res:read_body())
      assert.is_nil(err)
    end)

  end)
end
