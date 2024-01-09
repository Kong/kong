-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson   = require "cjson"

local strategies = helpers.all_strategies ~= nil and helpers.all_strategies or helpers.each_strategy

local PLUGIN_NAME = "tls-metadata-headers"

local tls_fixtures = { http_mock = {
  tls_server_block = [[
    server {
        server_name tls_test_client;
        listen 10121;

        location = /example_client {
            # Combined cert, contains client first and intermediate second
            proxy_ssl_certificate ]] .. helpers.get_fixtures_path() .. [[/good_tls_client.crt;
            proxy_ssl_certificate_key ]] .. helpers.get_fixtures_path() .. [[/good_tls_client.key;
            proxy_ssl_name example.com;
            # enable send the SNI sent to server
            proxy_ssl_server_name on;
            proxy_set_header Host example.com;

            proxy_pass https://127.0.0.1:9443/get;
        }

        location = /bad_client {
            proxy_ssl_certificate ]] .. helpers.get_fixtures_path() .. [[/bad_tls_client.crt;
            proxy_ssl_certificate_key ]] .. helpers.get_fixtures_path() .. [[/bad_tls_client.key;
            proxy_ssl_name example.com;
            proxy_set_header Host example.com;

            proxy_pass https://127.0.0.1:9443/get;
        }

    }
  ]], }
}

for _, strategy in strategies() do
  describe("Plugin: tls-metadata-headers (access) [#" .. strategy .. "]", function()
    local proxy_client, proxy_ssl_client, tls_client
    local bp
    local service_https, route_https
    local db_strategy = strategy ~= "off" and strategy or nil

    lazy_setup(function()
      bp = helpers.get_db_utils(db_strategy, {
        "routes",
        "services",
        "plugins",
      }, { "tls-metadata-headers", })

      service_https = bp.services:insert{
        protocol = "https",
        port     = helpers.mock_upstream_ssl_port,
        host     = helpers.mock_upstream_ssl_host,
      }

      route_https = bp.routes:insert {
        hosts   = { "example.com" },
        service = { id = service_https.id, },
      }

      assert(bp.plugins:insert {
        name = "tls-metadata-headers",
        route = { id = route_https.id },
        config = { inject_client_cert_details = true, },
      })

      assert(helpers.start_kong({
        database   = db_strategy,
        plugins = "bundled,tls-metadata-headers",
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }, nil, nil, tls_fixtures))

      proxy_client = helpers.proxy_client()
      proxy_ssl_client = helpers.proxy_ssl_client()
      tls_client = helpers.http_client("127.0.0.1", 10121)
    end)

    lazy_teardown(function()
      if proxy_client then
        proxy_client:close()
      end

      if proxy_ssl_client then
        proxy_ssl_client:close()
      end

      if tls_client then
        tls_client:close()
      end

      helpers.stop_kong()
    end)



    describe(PLUGIN_NAME .. " test", function()
      it("returns HTTP 200 on https request", function()
        local res = assert(tls_client:send {
          method  = "GET",
          path    = "/example_client",
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.is_nil(json.headers["X-Client-Cert"])
      end)

      it("returns HTTP 200 on https request if certificate validation passed", function()
        local res = assert(tls_client:send {
          method  = "GET",
          path    = "/bad_client",
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.is_nil(json.headers["X-Client-Cert"])
      end)

      it("returns HTTP 200 on http request no certificate passed in request", function()
        local res = assert(proxy_ssl_client:send {
          method  = "GET",
          path = "/get",
          headers = {
            host = "example.com",
          }
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.is_nil(json.headers["X-Client-Cert"])
      end)

    end)



  end)
end
