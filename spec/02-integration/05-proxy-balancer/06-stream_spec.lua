local helpers = require "spec.helpers"


for _, strategy in helpers.each_strategy() do
  describe("Balancer: least-connections [#" .. strategy .. "]", function()
    local MESSAGE = "echo, ping, pong. echo, ping, pong. echo, ping, pong.\n"
    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "upstreams",
        "targets",
        "plugins",
      })

      local upstream = bp.upstreams:insert({
        name = "tcp-upstream",
        algorithm = "least-connections",
      })

      bp.targets:insert({
        upstream = upstream,
        target = helpers.mock_upstream_host .. ":" .. helpers.mock_upstream_stream_port,
        weight = 100,
      })

      local service = bp.services:insert {
        host     = "tcp-upstream",
        port     = helpers.mock_upstream_stream_port,
        protocol = "tcp",
      }

      bp.routes:insert {
        destinations = {
          { port = 19000 },
        },
        protocols = {
          "tcp",
        },
        service = service,
      }

      local upstream_retries = bp.upstreams:insert({
        name = "tcp-upstream-retries",
        algorithm = "least-connections",
      })

      bp.targets:insert({
        upstream = upstream_retries,
        target = helpers.mock_upstream_host .. ":15000",
        weight = 300,
      })

      bp.targets:insert({
        upstream = upstream_retries,
        target = helpers.mock_upstream_host .. ":15001",
        weight = 200,
      })

      bp.targets:insert({
        upstream = upstream_retries,
        target = helpers.mock_upstream_host .. ":" .. helpers.mock_upstream_stream_port,
        weight = 100,
      })

      local service_retries = bp.services:insert {
        host     = "tcp-upstream-retries",
        port     = helpers.mock_upstream_stream_port,
        protocol = "tcp",
      }

      bp.routes:insert {
        destinations = {
          { port = 18000 },
        },
        protocols = {
          "tcp",
        },
        service = service_retries,
      }

      helpers.start_kong({
        database = strategy,
        stream_listen = helpers.get_proxy_ip(false) .. ":19000," ..
                        helpers.get_proxy_ip(false) .. ":18000",
        nginx_conf = "spec/fixtures/custom_nginx.template",
        proxy_listen = "off",
        admin_listen = "off",
      })
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    it("balances by least-connections", function()
      for _ = 1, 2 do
        local tcp_client = ngx.socket.tcp()
        assert(tcp_client:connect(helpers.get_proxy_ip(false), 19000))
        assert(tcp_client:send(MESSAGE))
        local body = assert(tcp_client:receive("*a"))
        assert.equal(MESSAGE, body)
        assert(tcp_client:close())
      end
    end)

    it("balances by least-connections with retries", function()
      for _ = 1, 2 do
        local tcp_client = ngx.socket.tcp()
        assert(tcp_client:connect(helpers.get_proxy_ip(false), 18000))
        assert(tcp_client:send(MESSAGE))
        local body = assert(tcp_client:receive("*a"))
        assert.equal(MESSAGE, body)
        assert(tcp_client:close())
      end
    end)
  end)
end
