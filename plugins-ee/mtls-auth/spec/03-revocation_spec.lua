-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local pl_file = require "pl.file"
local cjson   = require "cjson"

local strategies = helpers.all_strategies ~= nil and helpers.all_strategies or helpers.each_strategy

local CA = pl_file.read("/kong-plugin/spec/fixtures/ocsp-responder-docker/certificates/ca.pem")

--[[
What does pongo do in .pongo/ocspserver.yml:
cd plugins-ee/mtls-auth/spec/fixtures/ocsp-responder-docker
docker build -t ocsp-responder-docker .
docker run -it -p2560:2560 -p8080:8080 --rm -v (pwd)/certificates:/data ocsp-responder-docker
<Ctrl+C to stop the container>
]]--


local mtls_fixtures = { http_mock = {
  mtls_server_block = [[
    server {
        server_name mtls_test_client;
        listen 10121;

        location = /valid_client {
          # Combined cert, contains client first and intermediate second
          proxy_ssl_certificate ../spec/fixtures/ocsp-responder-docker/certificates/valid.pem;
          proxy_ssl_certificate_key ../spec/fixtures/ocsp-responder-docker/certificates/valid.pem.key;
          proxy_ssl_name example.com;
          # enable send the SNI sent to server
          proxy_ssl_server_name on;
          proxy_set_header Host example.com;

          proxy_pass https://127.0.0.1:9443/get;
        }

        location = /valid_client_proxy {
          # Combined cert, contains client first and intermediate second
          proxy_ssl_certificate ../spec/fixtures/ocsp-responder-docker/certificates/validproxy.pem;
          proxy_ssl_certificate_key ../spec/fixtures/ocsp-responder-docker/certificates/validproxy.pem.key;
          proxy_ssl_name exampleproxy.com;
          # enable send the SNI sent to server
          proxy_ssl_server_name on;
          proxy_set_header Host exampleproxy.com;

          proxy_pass https://127.0.0.1:9443/get;
        }

        location = /valid_client_bad_proxy {
          # Combined cert, contains client first and intermediate second
          # We use a second valid certificate here to defeat the DN -> Consumer cache
          proxy_ssl_certificate ../spec/fixtures/ocsp-responder-docker/certificates/valid2.pem;
          proxy_ssl_certificate_key ../spec/fixtures/ocsp-responder-docker/certificates/valid2.pem.key;
          proxy_ssl_name examplebadproxy.com;
          # enable send the SNI sent to server
          proxy_ssl_server_name on;
          proxy_set_header Host examplebadproxy.com;

          proxy_pass https://127.0.0.1:9443/get;
        }

        location = /revoked_client {
          # Combined cert, contains client first and intermediate second
          proxy_ssl_certificate ../spec/fixtures/ocsp-responder-docker/certificates/revoked.pem;
          proxy_ssl_certificate_key ../spec/fixtures/ocsp-responder-docker/certificates/revoked.pem.key;
          proxy_ssl_name example.com;
          # enable send the SNI sent to server
          proxy_ssl_server_name on;
          proxy_set_header Host example.com;

          proxy_pass https://127.0.0.1:9443/get;
        }

        location = /revoked_client_proxy {
          # Combined cert, contains client first and intermediate second
          proxy_ssl_certificate ../spec/fixtures/ocsp-responder-docker/certificates/revoked.pem;
          proxy_ssl_certificate_key ../spec/fixtures/ocsp-responder-docker/certificates/revoked.pem.key;
          proxy_ssl_name exampleproxy.com;
          # enable send the SNI sent to server
          proxy_ssl_server_name on;
          proxy_set_header Host exampleproxy.com;

          proxy_pass https://127.0.0.1:9443/get;
        }

        location = /revoked_client_bad_proxy {
          # Combined cert, contains client first and intermediate second
          proxy_ssl_certificate ../spec/fixtures/ocsp-responder-docker/certificates/revoked.pem;
          proxy_ssl_certificate_key ../spec/fixtures/ocsp-responder-docker/certificates/revoked.pem.key;
          proxy_ssl_name examplebadproxy.com;
          # enable send the SNI sent to server
          proxy_ssl_server_name on;
          proxy_set_header Host examplebadproxy.com;

          proxy_pass https://127.0.0.1:9443/get;
        }
    }
  ]], }
}

for _, strategy in strategies() do
  describe("Plugin: mtls-auth (revocation) [#" .. strategy .. "]", function()
    local proxy_client, admin_client, proxy_ssl_client, mtls_client
    local bp, db
    local consumer, consumer_proxy, service, route
    local ca_cert
    local db_strategy = strategy ~= "off" and strategy or nil

    lazy_setup(function()
      bp, db = helpers.get_db_utils(db_strategy, {
        "routes",
        "services",
        "plugins",
        "consumers",
        "ca_certificates",
        "mtls_auth_credentials",
      }, { "mtls-auth", })

      consumer = bp.consumers:insert {
        username = "valid@konghq.com"
      }

      consumer_proxy = bp.consumers:insert {
        username = "validproxy@konghq.com"
      }

      bp.consumers:insert {
        username = "valid2@konghq.com"
      }

      service = bp.services:insert{
        protocol = "https",
        port     = helpers.mock_upstream_ssl_port,
        host     = helpers.mock_upstream_ssl_host,
      }

      route = bp.routes:insert {
        hosts   = { "example.com" },
        service = { id = service.id, },
      }

      local route_proxy = bp.routes:insert {
        hosts   = { "exampleproxy.com" },
        service = { id = service.id, },
      }

      local route_bad_proxy = bp.routes:insert {
        hosts   = { "examplebadproxy.com" },
        service = { id = service.id, },
      }

      ca_cert = assert(db.ca_certificates:insert({
        cert = CA,
      }))

      assert(bp.plugins:insert {
        name = "mtls-auth",
        route = { id = route.id },
        config = {
          ca_certificates = { ca_cert.id, },
          revocation_check_mode = "STRICT",
          cert_cache_ttl = 0,
          cache_ttl = 0,
        },
      })

      assert(bp.plugins:insert {
        name = "mtls-auth",
        route = { id = route_proxy.id },
        config = {
          ca_certificates = { ca_cert.id, },
          revocation_check_mode = "STRICT",
          http_proxy_host = "squidcustom",
          http_proxy_port = 3128,
          cert_cache_ttl = 0,
          cache_ttl = 0,
        },
      })

      assert(bp.plugins:insert {
        name = "mtls-auth",
        route = { id = route_bad_proxy.id },
        config = {
          ca_certificates = { ca_cert.id, },
          revocation_check_mode = "STRICT",
          http_proxy_host = "squidcustom",
          http_proxy_port = 3129, -- this port is not open so HTTP CONNECT will fail
          cert_cache_ttl = 0,
          cache_ttl = 0,
        },
      })

      assert(helpers.start_kong({
        database   = db_strategy,
        plugins = "bundled,mtls-auth",
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }, nil, nil, mtls_fixtures))

      proxy_client = helpers.proxy_client()
      proxy_ssl_client = helpers.proxy_ssl_client()
      mtls_client = helpers.http_client("127.0.0.1", 10121)
      admin_client = helpers.admin_client()
    end)

    lazy_teardown(function()
      if proxy_client then
        proxy_client:close()
      end

      if proxy_ssl_client then
        proxy_ssl_client:close()
      end

      if mtls_client then
        mtls_client:close()
      end

      if admin_client then
        admin_client:close()
      end

      helpers.stop_kong()
    end)

    describe("valid certificate", function()
      it("returns HTTP 200 on https request if valid certificate passed with no proxy", function()
        local res = assert(mtls_client:send {
          method  = "GET",
          path    = "/valid_client",
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("valid@konghq.com", json.headers["x-consumer-username"])
        assert.equal(consumer.id, json.headers["x-consumer-id"])
      end)

      it("returns HTTP 200 on https request if valid certificate passed with proxy", function()
        local res = assert(mtls_client:send {
          method  = "GET",
          path    = "/valid_client_proxy",
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("validproxy@konghq.com", json.headers["x-consumer-username"])
        assert.equal(consumer_proxy.id, json.headers["x-consumer-id"])
      end)

      it("returns HTTP 401 on https request if valid certificate passed with bad proxy configuration", function()
        local res = assert(mtls_client:send {
          method  = "GET",
          path    = "/valid_client_bad_proxy",
        })

        local body = assert.res_status(401, res)
        local json = cjson.decode(body)
        assert.equal("TLS certificate failed verification", json.message)
      end)
    end)

    describe("revoked certificate", function()
      it("returns HTTP 401 on https request if revoked certificate passed with no proxy", function()
        local res = assert(mtls_client:send {
          method  = "GET",
          path    = "/revoked_client",
        })

        local body = assert.res_status(401, res)
        local json = cjson.decode(body)
        assert.equal("TLS certificate failed verification", json.message)
      end)

      it("returns HTTP 401 on https request if revoked certificate passed with proxy", function()
        local res = assert(mtls_client:send {
          method  = "GET",
          path    = "/revoked_client_proxy",
        })

        local body = assert.res_status(401, res)
        local json = cjson.decode(body)
        assert.equal("TLS certificate failed verification", json.message)
      end)

      it("returns HTTP 401 on https request if revoked certificate passed with bad proxy configuration", function()
        local res = assert(mtls_client:send {
          method  = "GET",
          path    = "/revoked_client_bad_proxy",
        })

        local body = assert.res_status(401, res)
        local json = cjson.decode(body)
        assert.equal("TLS certificate failed verification", json.message)
      end)
    end)
  end)
end
