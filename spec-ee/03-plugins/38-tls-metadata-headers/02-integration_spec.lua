-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson = require "cjson"
local escape_uri = ngx.escape_uri
local openssl_x509 = require "resty.openssl.x509"
local to_hex = require "resty.string".to_hex

local strategies = helpers.all_strategies ~= nil and helpers.all_strategies or helpers.each_strategy

local fixture_path = "spec/fixtures/tls-metadata-headers/"
local fixture_path_from_prefix = "../" .. fixture_path


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
            proxy_ssl_certificate ]] .. fixture_path_from_prefix .. [[/good_tls_client.crt;
            proxy_ssl_certificate_key ]] .. fixture_path_from_prefix .. [[/good_tls_client.key;
            proxy_ssl_name tls.test;
            # enable send the SNI sent to server
            proxy_ssl_server_name on;
            proxy_set_header Host tls.test;

            proxy_pass https://127.0.0.1:9443/get;
        }

        location = /bad_client {
            proxy_ssl_certificate ]] .. fixture_path_from_prefix .. [[/bad_tls_client.crt;
            proxy_ssl_certificate_key ]] .. fixture_path_from_prefix .. [[/bad_tls_client.key;
            proxy_ssl_name tls.test;
            proxy_set_header Host tls.test;

            proxy_pass https://127.0.0.1:9443/get;
        }

        location = /mtls-auth-good_client {
          proxy_ssl_certificate ]] .. fixture_path_from_prefix .. [[/client_example.com.crt;
          proxy_ssl_certificate_key ]] .. fixture_path_from_prefix .. [[/client_example.com.key;
          proxy_ssl_name example.com;
          # enable send the SNI sent to server
          proxy_ssl_server_name on;
          proxy_set_header Host example.com;

          proxy_pass https://127.0.0.1:9443/get;
      }

        location = /another {
          proxy_ssl_certificate ]] .. fixture_path_from_prefix .. [[/good_tls_client.crt;
          proxy_ssl_certificate_key ]] .. fixture_path_from_prefix .. [[/good_tls_client.key;
          proxy_ssl_name tls.test;
          proxy_set_header Host tls.test;

          proxy_pass https://127.0.0.1:9443/anything;
      }

        location = /intermediate_client {
            proxy_ssl_certificate ]] .. fixture_path_from_prefix .. [[/intermediate_client_example.com.crt;
            proxy_ssl_certificate_key ]] .. fixture_path_from_prefix .. [[/intermediate_client_example.com.key;
            proxy_ssl_name example.com;
            proxy_set_header Host example.com;
            proxy_pass https://127.0.0.1:9443/get;
        }

        location = /good_client_multi-chain {
            proxy_ssl_certificate ]] .. fixture_path_from_prefix .. [[/client_example.com.crt;
            proxy_ssl_certificate_key ]] .. fixture_path_from_prefix .. [[/client_example.com.key;
            proxy_ssl_name example.com;
            proxy_set_header Host example.com;
            proxy_pass https://127.0.0.1:9443/get;
        }

    }
  ]], }
}

for _, strategy in strategies() do
  describe("Plugin: tls plugins (access) [#" .. strategy .. "]", function()
    local proxy_ssl_client, tls_client
    local bp, db
    local ca_cert, intermediate_cert
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

      intermediate_cert = assert(db.ca_certificates:insert({
        cert = read_fixture("intermediate_ca.crt"),
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
        config = {  skip_consumer_lookup = true,
                    allow_partial_chain = true,
                    ca_certificates = {
                      ca_cert.id,
                      intermediate_cert.id,
                    },
                  },
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
        assert.equal("101B76125AB64444CEFA66A89D5F60A100E8B6B1", json.headers["x-client-cert-serial"])
        assert.equal("emailAddress=test@test.test,CN=test.com,OU=Kong Inc,O=Kong Inc,L=San Francisco,ST=California,C=US", json.headers["x-client-cert-issuer-dn"])
        assert.equal("emailAddress=test@test.test,CN=test.com,OU=Kong Inc,O=Kong Inc,L=San Francisco,ST=California,C=US", json.headers["x-client-cert-subject-dn"])
        assert.equal("8adf60fa5f9710f28a4e749b8871926684ac8779", json.headers["x-client-cert-fingerprint"])
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

      it("returns HTTP 200 on https request if intermediate certificate validation passed", function()
        local res = assert(tls_client:send {
          method  = "GET",
          path    = "/intermediate_client",
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        local m = assert(ngx.re.match(read_fixture("intermediate_client_example.com.crt"),
                                [[^\X+(?<cert>-----BEGIN CERTIFICATE-----\X+-----END CERTIFICATE-----\X*)]]))

        local cert = escape_uri(m["cert"])
        assert.equal(cert, json.headers["x-client-cert"])
        assert.equal("1001", json.headers["x-client-cert-serial"])
        assert.equal("CN=Interm.", json.headers["x-client-cert-issuer-dn"])
        assert.equal("CN=1.example.com", json.headers["x-client-cert-subject-dn"])
        assert.equal("4cf374a3d5a4afc25b87b7bb315b4140dfc69165", json.headers["x-client-cert-fingerprint"])
      end)

      it("returns HTTP 200 on https request if multi-chain certificate validation passed", function()
        local res = assert(tls_client:send {
          method  = "GET",
          path    = "/good_client_multi-chain",
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        local certs = read_fixture("client_example.com.crt")
        local it = assert(ngx.re.gmatch(certs,
                          [[(-----[BEGIN \S\ ]+?-----[\S\s]+?-----[END \S\ ]+?-----\X)]]))
        local client_cert = assert(it()[1])
        local escaped_client_cert = escape_uri(client_cert)
        local x509 = assert(openssl_x509.new(client_cert, "PEM"))

        -- x-client-cert should contain a single certificate
        assert.equal("string", type(json.headers["x-client-cert"]))

        assert.equal(escaped_client_cert, json.headers["x-client-cert"])
        assert.equal("a65e0ff498d954b0ac33fd4f35f6d02de145667b", json.headers["x-client-cert-fingerprint"])

        local xfcc_element = json.headers["x-forwarded-client-cert"]

        local expected_cert = escaped_client_cert
        local expected_subject = "\"CN=foo@example.com,O=Kong Testing,ST=California,C=US\""
        local expected_hash = to_hex(x509:digest("sha256"))
        local expected_chain = escape_uri(certs)
        local expected_xfcc = string.format("Cert=%s;Subject=%s;Hash=%s;Chain=%s",
                                            expected_cert, expected_subject, expected_hash, expected_chain)

        local xfcc_cert = ngx.re.match(xfcc_element, [[Cert=([^;]+);]])
        assert.equal(expected_cert, xfcc_cert[1])
        local xfcc_subject = ngx.re.match(xfcc_element, [[Subject=("[^";]+");]])
        assert.equal(expected_subject, xfcc_subject[1])
        local xfcc_hash = ngx.re.match(xfcc_element, [[Hash=([^;]+);]])
        assert.equal(expected_hash, xfcc_hash[1])
        local xfcc_chain = ngx.re.match(xfcc_element, [[Chain=(\S+0A)]])
        assert.equal(expected_chain, xfcc_chain[1])
        assert.equal(expected_xfcc, xfcc_element)

        -- should append the xfcc element correcly
        local original_xfcc = "Subject=\"CN=test\";Hash=194a2e827dd41919e5385a8776ddc211326dd7fc78752c671e35001ba8ef1936"
        res = assert(tls_client:send {
          method  = "GET",
          path    = "/good_client_multi-chain",
          headers = {
            ["x-forwarded-client-cert"] = original_xfcc,
          }
        })
        body = assert.res_status(200, res)
        json = cjson.decode(body)
        local xfcc = json.headers["x-forwarded-client-cert"]
        assert.equal(original_xfcc .. "," .. xfcc_element, xfcc)
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
