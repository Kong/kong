local helpers = require "spec.helpers"
local pl_file = require "pl.file"
local cjson = require "cjson"


local TEST_CONF = helpers.test_conf


for _, strategy in helpers.each_strategy() do
  describe("#stream Proxying [#" .. strategy .. "]", function()
    local bp

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
        host_header = "ssl-hello.com",
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
        proxy_listen = "off",
        admin_listen = "off",
        stream_listen = helpers.get_proxy_ip(false) .. ":19000," ..
                        helpers.get_proxy_ip(false) .. ":19443 ssl",
        proxy_stream_error_log = "/tmp/error.log",
      }))
    end)

    after_each(function()
      helpers.stop_kong()
    end)

    it("tls", function()
      local tcp = ngx.socket.tcp()
      assert(tcp:connect(helpers.get_proxy_ip(true), 19443))
      assert(tcp:sslhandshake(nil, "ssl-hello.com", false))
      assert(tcp:send("get_sni\n"))
      local body = assert(tcp:receive("*a"))
      ngx.log(ngx.ERR, body)
      assert.equal("ssl-hello.com\n", body)
      tcp:close()
    end)
  end)
end
