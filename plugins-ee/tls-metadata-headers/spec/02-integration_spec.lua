-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson = require "cjson"
local pl_path = require "pl.path"
local escape_uri = ngx.escape_uri

local strategies = helpers.all_strategies ~= nil and helpers.all_strategies or helpers.each_strategy

local fixture_path do
  -- this code will get debug info and from that determine the file
  -- location, so fixtures can be found based of this path
  local info = debug.getinfo(function() end)
  fixture_path = info.source
  if fixture_path:sub(1,1) == "@" then
    fixture_path = fixture_path:sub(2, -1)
  end
  fixture_path = pl_path.splitpath(fixture_path) .. "/fixtures/"
end


local function read_fixture(filename)
  local content  = assert(helpers.utils.readfile(fixture_path .. filename))
   return content
end


local tls_fixtures = { http_mock = {
  tls_server_block = [[
    server {
        server_name tls_test_client;
        listen 10121;

        location = /good_client {
            proxy_ssl_certificate /kong-plugin/spec/fixtures/good_tls_client.crt;
            proxy_ssl_certificate_key /kong-plugin/spec/fixtures/good_tls_client.key;
            proxy_ssl_name tls.test;
            # enable send the SNI sent to server
            proxy_ssl_server_name on;
            proxy_set_header Host tls.test;

            proxy_pass https://127.0.0.1:9443/get;
        }

        location = /bad_client {
            proxy_ssl_certificate /kong-plugin/spec/fixtures/bad_tls_client.crt;
            proxy_ssl_certificate_key /kong-plugin/spec/fixtures/bad_tls_client.key;
            proxy_ssl_name tls.test;
            proxy_set_header Host tls.test;

            proxy_pass https://127.0.0.1:9443/get;
        }

        location = /mtls-auth-good_client {
          proxy_ssl_certificate /kong-plugin/spec/fixtures/client_example.com.crt;
          proxy_ssl_certificate_key /kong-plugin/spec/fixtures/client_example.com.key;
          proxy_ssl_name example.com;
          # enable send the SNI sent to server
          proxy_ssl_server_name on;
          proxy_set_header Host example.com;

          proxy_pass https://127.0.0.1:9443/get;
      }

        location = /another {
          proxy_ssl_certificate /kong-plugin/spec/fixtures/good_tls_client.crt;
          proxy_ssl_certificate_key /kong-plugin/spec/fixtures/good_tls_client.key;
          proxy_ssl_name tls.test;
          proxy_set_header Host tls.test;

          proxy_pass https://127.0.0.1:9443/anything;
      }

    }
  ]], }
}

for _, strategy in strategies() do
  describe("Plugin: tls plugins (access) [#" .. strategy .. "]", function()
    local proxy_ssl_client, tls_client
    local bp, db
    local ca_cert
    local service_https, route_https1, route_https2, route_https3
    local db_strategy = strategy ~= "off" and strategy or nil

    lazy_setup(function()
      bp, db = helpers.get_db_utils(db_strategy, {
        "routes",
        "services",
        "plugins",
        "ca_certificates",
      }, { "tls-handshake-modifier", "tls-metadata-headers", "mtls-auth", })

      service_https = bp.services:insert{
        protocol = "https",
        port     = helpers.mock_upstream_ssl_port,
        host     = helpers.mock_upstream_ssl_host,
      }

      route_https1 = bp.routes:insert {
        hosts   = { "tls.test" },
        service = { id = service_https.id, },
        strip_path = false,
        paths = { "/get"},
      }

      assert(bp.plugins:insert {
        name = "tls-handshake-modifier",
        route = { id = route_https1.id },
      })

      assert(bp.plugins:insert {
        name = "tls-metadata-headers",
        route = { id = route_https1.id },
        config = { inject_client_cert_details = true,
          },
      })

      route_https2 = bp.routes:insert {
        service = { id = service_https.id, },
        hosts   = { "tls.test" },
        strip_path = false,
        paths = { "/anything"},
      }

      assert(bp.plugins:insert {
        name = "tls-handshake-modifier",
        route = { id = route_https2.id },
      })

      assert(bp.plugins:insert {
        name = "tls-metadata-headers",
        route = { id = route_https2.id },
        config = { inject_client_cert_details = true,
          client_cert_header_name = "X-Client-Cert-Custom",
          client_serial_header_name = "X-Client-Cert-Serial-Custom",
          client_cert_issuer_dn_header_name = "X-Client-Cert-Issuer-DN-Custom",
          client_cert_subject_dn_header_name = "X-Client-Cert-Subject-DN-Custom",
          client_cert_fingerprint_header_name = "X-Client-Cert-Fingerprint-Custom",
        },
      })

      ca_cert = assert(db.ca_certificates:insert({
        cert = read_fixture("ca.crt"),
      }))

      route_https3 = bp.routes:insert {
        service = { id = service_https.id, },
        hosts   = { "example.com" },
        strip_path = false,
        paths = { "/get"},
      }

      assert(bp.plugins:insert {
        name = "mtls-auth",
        route = { id = route_https3.id },
        config = { skip_consumer_lookup = true,
          ca_certificates = { ca_cert.id, }, },
      })

      assert(bp.plugins:insert {
        name = "tls-metadata-headers",
        route = { id = route_https3.id },
        config = { inject_client_cert_details = true,
          },
      })

      assert(helpers.start_kong({
        database   = db_strategy,
        plugins = "bundled,tls-handshake-modifier,tls-metadata-headers,mtls-auth",
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }, nil, nil, tls_fixtures))

      proxy_ssl_client = helpers.proxy_ssl_client()
      tls_client = helpers.http_client("127.0.0.1", 10121)
    end)

    lazy_teardown(function()

      if proxy_ssl_client then
        proxy_ssl_client:close()
      end

      if tls_client then
        tls_client:close()
      end

      helpers.stop_kong()
    end)

    describe("valid certificate test using tls-handshake-modifier plugin to request client certificate", function()
      it("returns HTTP 200 on https request if certificate validation passed", function()
        local res = assert(tls_client:send {
          method  = "GET",
          path    = "/good_client",
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal(escape_uri(read_fixture("good_tls_client.crt")), json.headers["x-client-cert"])
        assert.equal("65", json.headers["x-client-cert-serial"])
        assert.equal("emailAddress=test@test.com,OU=PS,O=Kong,L=Sydney,ST=NSW,C=AU", json.headers["x-client-cert-issuer-dn"])
        assert.equal("emailAddress=test@test.com,OU=PS,O=Kong,L=Sydney,ST=NSW,C=AU", json.headers["x-client-cert-subject-dn"])
        assert.equal("88b74971771571c618e6c6215ba4f6ef71ccc2c7", json.headers["x-client-cert-fingerprint"])
      end)

       it("returns HTTP 200 on https request if certificate is provided by client - plugin does not validate certificate", function()
        local res = assert(tls_client:send {
          method  = "GET",
          path    = "/bad_client",
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal(escape_uri(read_fixture("bad_tls_client.crt")), json.headers["x-client-cert"])
        assert.equal("A50E6D5692B796E2", json.headers["x-client-cert-serial"])
        assert.equal("emailAddress=agentzh@gmail.com,CN=test.com,OU=OpenResty,O=OpenResty,L=San Francisco,ST=California,C=US", json.headers["x-client-cert-issuer-dn"])
        assert.equal("emailAddress=agentzh@gmail.com,CN=test.com,OU=OpenResty,O=OpenResty,L=San Francisco,ST=California,C=US", json.headers["x-client-cert-subject-dn"])
        assert.equal("f65fe7cb882d10dd0b3acefe5d2153c445bb0910", json.headers["x-client-cert-fingerprint"])
      end)

      it("returns HTTP 200 on http request with custom headers", function()
        local res = assert(tls_client:send {
          method  = "GET",
          path    = "/another",
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal(escape_uri(read_fixture("good_tls_client.crt")), json.headers["x-client-cert-custom"])
        assert.equal("65", json.headers["x-client-cert-serial-custom"])
        assert.equal("emailAddress=test@test.com,OU=PS,O=Kong,L=Sydney,ST=NSW,C=AU", json.headers["x-client-cert-issuer-dn-custom"])
        assert.equal("emailAddress=test@test.com,OU=PS,O=Kong,L=Sydney,ST=NSW,C=AU", json.headers["x-client-cert-subject-dn-custom"])
        assert.equal("88b74971771571c618e6c6215ba4f6ef71ccc2c7", json.headers["x-client-cert-fingerprint-custom"])
      end)

    end)

    describe("no certificate", function()

      it("returns HTTP 200 on http request no certificate passed in request", function()
        local res = assert(proxy_ssl_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            host = "tls.test",
          }
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.is_nil(json.headers["x-client-cert"])
        assert.is_nil(json.headers["x-client-cert-serial"])
        assert.is_nil(json.headers["x-client-cert-issuer-dn"])
        assert.is_nil(json.headers["x-client-cert-subject-dn"])
        assert.is_nil(json.headers["x-client-cert-fingerprint"])
      end)

    end)

    describe("valid certificate test using mtls-auth plugin to request client certificate", function()
      it("returns HTTP 200 on https request if certificate validation passed", function()
        local res = assert(tls_client:send {
          method  = "GET",
          path    = "/mtls-auth-good_client",
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal(escape_uri(read_fixture("client_example_validated.com.crt")), json.headers["x-client-cert"])
        assert.equal("2001", json.headers["x-client-cert-serial"])
        assert.equal("CN=Kong Testing Intermidiate CA,O=Kong Testing,ST=California,C=US", json.headers["x-client-cert-issuer-dn"])
        assert.equal("CN=foo@example.com,O=Kong Testing,ST=California,C=US", json.headers["x-client-cert-subject-dn"])
        assert.equal("a65e0ff498d954b0ac33fd4f35f6d02de145667b", json.headers["x-client-cert-fingerprint"])
      end)

    end)


  end)
end
