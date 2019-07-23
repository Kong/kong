local helpers = require "spec.helpers"
local ssl_fixtures = require "spec.fixtures.ssl"


local fixtures = {
  http_mock = {
    upstream_mtls = [[
      server {
          server_name example.com;
          listen 16798 ssl;

          ssl_certificate        ../spec/fixtures/mtls_certs/example.com.crt;
          ssl_certificate_key    ../spec/fixtures/mtls_certs/example.com.key;
          ssl_client_certificate ../spec/fixtures/mtls_certs/ca.crt;
          ssl_verify_client      on;
          ssl_session_tickets    off;
          ssl_session_cache      off;
          keepalive_requests     0;

          location = / {
              echo 'it works';
          }
      }
  ]]
  },
}


for _, strategy in helpers.each_strategy() do
  describe("mutual TLS authentication against upstream with DB: #" .. strategy, function()
    local proxy_client, admin_client
    local bp
    local service
    local certificate

    lazy_setup(function()
      bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "certificates",
      })

      service = assert(bp.services:insert({
        name = "protected-service",
        url = "https://127.0.0.1:16798/"
      }))

      certificate = assert(bp.certificates:insert({
        cert = ssl_fixtures.cert_client,
        key = ssl_fixtures.key_client,
      }))

      assert(bp.routes:insert({
        service = { id = service.id, },
        hosts = { "example.com", },
      }))

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }, nil, nil, fixtures))

      proxy_client = assert(helpers.proxy_client())
      admin_client = assert(helpers.admin_client())
    end)

    lazy_teardown(function()
      if proxy_client then
        proxy_client:close()
      end

      helpers.stop_kong()
    end)

    describe("no client certificate supplied", function()
      it("accessing protected upstream", function()
        local res = assert(proxy_client:send {
          path    = "/",
          headers = {
            ["Host"] = "example.com",
          }
        })

        local body = assert.res_status(400, res)
        assert.matches("400 No required SSL certificate was sent", body, nil, true)
      end)
    end)

    describe("#db client certificate supplied via service.client_certificate", function()
      lazy_setup(function()
        local res = assert(admin_client:patch("/services/" .. service.id, {
          body = {
            client_certificate = { id = certificate.id, },
          },
          headers = { ["Content-Type"] = "application/json" },
        }))

        assert.res_status(200, res)
      end)

      it("accessing protected upstream", function()
        local res = assert(proxy_client:send {
          path    = "/",
          headers = {
            ["Host"] = "example.com",
          }
        })

        local body = assert.res_status(200, res)
        assert.equals("it works", body)
      end)

      it("remove client_certificate removes access", function()
        local res = assert(admin_client:patch("/services/" .. service.id, {
          body = {
            client_certificate = ngx.null,
          },
          headers = { ["Content-Type"] = "application/json" },
        }))

        assert.res_status(200, res)

        res = assert(proxy_client:send {
          path    = "/",
          headers = {
            ["Host"] = "example.com",
          }
        })

        local body = assert.res_status(400, res)
        assert.matches("400 No required SSL certificate was sent", body, nil, true)
      end)
    end)
  end)
end
