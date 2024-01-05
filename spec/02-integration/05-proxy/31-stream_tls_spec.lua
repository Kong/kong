local helpers = require "spec.helpers"

for _, flavor in ipairs({ "traditional", "traditional_compatible" }) do
for _, strategy in helpers.each_strategy({"postgres"}) do
  describe("#stream Proxying [#" .. strategy .. "] [#" .. flavor .. "]", function()
    local bp
    local admin_client

    before_each(function()
      bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "upstreams",
        "plugins",
      }, {
        "logger",
      })

      local upstream_srv = bp.upstreams:insert({
        name = "upstream_srv",
      })

      bp.targets:insert {
        target = helpers.mock_upstream_host .. ":" ..
                 helpers.mock_upstream_stream_ssl_port,
        upstream = { id = upstream_srv.id },
      }

      local tls_srv = bp.services:insert({
        name = "tls",
        url = "tls://upstream_srv",
      })

      bp.routes:insert {
        name = "routes_stream",
        destinations = {
          {
            port = 19443,
          },
        },
        protocols = {
          "tls",
        },
        service = tls_srv,
      }

      bp.plugins:insert {
        name = "logger",
      }

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "logger",
        stream_listen = helpers.get_proxy_ip(false) .. ":19000,"
          .. helpers.get_proxy_ip(false) .. ":19001,"
          .. helpers.get_proxy_ip(false) .. ":19002,"
          .. helpers.get_proxy_ip(false) .. ":19003,"
          .. helpers.get_proxy_ip(false) .. ":19443 ssl",
        proxy_stream_error_log = "/tmp/error.log",
        router_flavor = flavor,
      }))
      admin_client = helpers.http_client("127.0.0.1", 9001)
    end)

    after_each(function()
      admin_client:close()
      helpers.stop_kong()
    end)

    it("tls not set host_header", function()
      local tcp = ngx.socket.tcp()
      assert(tcp:connect(helpers.get_proxy_ip(true), 19443))
      assert(tcp:sslhandshake(nil, "ssl-hello.test", false))
      assert(tcp:send("get_sni\n"))
      local body = assert(tcp:receive("*a"))
      assert.equal("nil\n", body)
      tcp:close()
    end)

    it("tls set preserve_host", function()
      local res = assert(admin_client:send {
        method  = "PATCH",
        path    = "/routes/routes_stream",
        body    = {
          preserve_host = true,
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      assert.res_status(200, res)
      local opt = {
        stream_enabled = true,
        stream_ip = "127.0.0.1",
        stream_port = 19003,
        timeout = 60,
      }
      helpers.wait_for_all_config_update(opt)

      local tcp = ngx.socket.tcp()
      assert(tcp:connect(helpers.get_proxy_ip(true), 19443))
      assert(tcp:sslhandshake(nil, "ssl-hello.test", false))
      assert(tcp:send("get_sni\n"))
      local body = assert(tcp:receive("*a"))
      assert.equal("ssl-hello.test\n", body)
      tcp:close()
    end)
    
    it("tls set host_header", function()
      -- clear preserve_host
      local res = assert(admin_client:send {
        method  = "PATCH",
        path    = "/routes/routes_stream",
        body    = {
          preserve_host = false,
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      assert.res_status(200, res)
      
      local opt = {
        stream_enabled = true,
        stream_port = 19003
      }
      helpers.wait_for_all_config_update(opt)

      local tcp = ngx.socket.tcp()
      assert(tcp:connect(helpers.get_proxy_ip(true), 19443))
      assert(tcp:sslhandshake(nil, "ssl-hello.test", false))
      assert(tcp:send("get_sni\n"))
      local body = assert(tcp:receive("*a"))
      assert.equal("nil\n", body)
      tcp:close()

      local res = assert(admin_client:send {
        method  = "PATCH",
        path    = "/upstreams/upstream_srv",
        body    = {
          host_header = "ssl-hello.test"
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      assert.res_status(200, res)
      helpers.wait_for_all_config_update(opt)

      local tcp = ngx.socket.tcp()
      assert(tcp:connect(helpers.get_proxy_ip(true), 19443))
      assert(tcp:sslhandshake(nil, "ssl-hello.test", false))
      assert(tcp:send("get_sni\n"))
      local body = assert(tcp:receive("*a"))
      assert.equal("ssl-hello.test\n", body)
      tcp:close()
    end)
  end)
end
end
