local helpers = require "spec.helpers"

for _, strategy in helpers.each_strategy() do

  describe("gRPC-Gateway [#" .. strategy .. "], settings: use_proto_names=true; enum_as_name=true; emit_defaults=false", function()
    local proxy_client -- luacheck: ignore

    lazy_setup(function()
      assert(helpers.start_grpc_target())

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
          use_proto_names = true,
          enum_as_name = true,
          emit_defaults = false,
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
  end)
end
