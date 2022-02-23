-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson   = require "cjson"

local strategies = helpers.all_strategies ~= nil and helpers.all_strategies or helpers.each_strategy

local client_crt_good = [[-----BEGIN%20CERTIFICATE-----%0AMIIFQDCCAygCAWUwDQYJKoZIhvcNAQEFBQAwZjELMAkGA1UEBhMCQVUxDDAKBgNV%0ABAgMA05TVzEPMA0GA1UEBwwGU3lkbmV5MQ0wCwYDVQQKDARLb25nMQswCQYDVQQL%0ADAJQUzEcMBoGCSqGSIb3DQEJARYNdGVzdEB0ZXN0LmNvbTAeFw0yMDA2MTAyMzIx%0AMThaFw0yMTA2MTAyMzIxMThaMGYxCzAJBgNVBAYTAkFVMQwwCgYDVQQIDANOU1cx%0ADzANBgNVBAcMBlN5ZG5leTENMAsGA1UECgwES29uZzELMAkGA1UECwwCUFMxHDAa%0ABgkqhkiG9w0BCQEWDXRlc3RAdGVzdC5jb20wggIiMA0GCSqGSIb3DQEBAQUAA4IC%0ADwAwggIKAoICAQDH1JuwgFDvXpLA0kXhFoDhM%2FIp7J3GVwkulSyamKbTvfNTcV7B%0AfCCwwyP%2B%2BXLZ7E6k3POnQwtUv6oDT7TldmutgZvlVfc9hUnMhoe2PEL6qbDZbzto%0AUE7GDgpASHIbNTeU8AvZY9cCaFg9aF3gK36NSOAmBXMXsISN28MiVcxFZlgpZfpk%0ALIAvtaUXD6TMxpC2H5DCcVDlv7ikcwpoN5lhTP3WtpuGN8IIA8euf0Bsqr%2BUfWtS%0AgcOPWFBipY1aOuzSZ%2FVacHxyiPfM7pMhp3O3Cbuqf5hhadtDGCq8ZeBORBpJyfXh%0AhPx3j%2FjWtapinQO0Sl%2B4ODZA%2F0%2F41d8%2Bsh5ZPuNzsDNzufiH1PQkJuDcLa1DivTM%0AsHD1NYFQpBLKZU9F6Vr7Pu6ntckW%2FiRfXZCQuYusBzk2xGquuMd4LqLmTstXsgDy%0AiYoeAF4JsypsPLorJrmR%2F64d3urNTUeiZfXvAwV3sFLxJg8eekdEVXSGIVl7wmDZ%0A2guYq6jG33dvmyq6U7Rbtpi4qWJdMOclboU7p6C06T8FPvyDMZUolJ3fghN7HIHZ%0AG4PDDQXTjCtG2MAY1wwxnLj5RI0iLt8RA15p%2BNkdWwuWCb%2FYA03hb4vafjk%2Bfqgj%0AJqC%2FwI2d%2FFLCqhET1qqHXB%2FwMKCpVra%2BaBuDB1QIdK3CbHPUNpoqcMreVwIDAQAB%0AMA0GCSqGSIb3DQEBBQUAA4ICAQBPv3626lgITncOD5qM8t0NIqamJMKFGh0VQUHY%0AIBO9weGbczyP72ZzXwxTKinCHirVLRiGjItrD4zAPDuMsQ1NCMHjmytXlS0jnuMw%0Ai2xWtcXoKuOlA2Y%2FAzU9s%2FSkZNTUgnZBVCbPp8q%2BezJCtODgY1x0xDS6KJgWCCTQ%0AYVTt4vFyfWGTJYS9cgeYI%2Fq8znZOs8slRwgSI063ICD5TyHQeQWDqTsYAssVaMt6%0AamiNKx1DKEgIbgTOEqUzYeZpBqNL%2FpRxkHB9PAbUE57%2Bn3zSBKmxXQfmAoCDGGhy%0AIPmYqh3FJFx98iud%2F%2FO5awC4184A7eGyC%2BnVapv23yXaQHoEeH7huiNJwucml3Ja%0AL2AY0VeEmj1HKYbwh4SV6CVjgTv002tiDjId04nf4DLL6hU%2BYjBsg9z6K1ZXrIUB%0AWX9UIpPlXv3N3Uq%2BR%2B1sidfYNwOcAy5VLbj%2BmwN2uHdCH2DFkvo9W5abCMaxLlKh%0AtH3V9xijK54Ph79ySkgyjC20o%2BKsL%2BZJR75fniTjn716m%2BuJys4B%2BBWGJCgDzi1X%0ApRGnW6Yj1IAErPRtKQU3FRG7frNrpRPTt%2FF8tPTPBqi2bSeMaCn2X2u0gVDo7FhX%0Apkh6xnPZ%2FqHUXwDqjngDinNQ8zTMgxt%2Fsv84zabDAf67ZkAyYriQx8H6kWULgcou%0A1h%2BbNg%3D%3D%0A-----END%20CERTIFICATE-----%0A]]
local client_crt_bad = [[-----BEGIN%20CERTIFICATE-----%0AMIICqTCCAhICCQClDm1WkreW4jANBgkqhkiG9w0BAQUFADCBlzELMAkGA1UEBhMC%0AVVMxEzARBgNVBAgMCkNhbGlmb3JuaWExFjAUBgNVBAcMDVNhbiBGcmFuY2lzY28x%0AEjAQBgNVBAoMCU9wZW5SZXN0eTESMBAGA1UECwwJT3BlblJlc3R5MREwDwYDVQQD%0ADAh0ZXN0LmNvbTEgMB4GCSqGSIb3DQEJARYRYWdlbnR6aEBnbWFpbC5jb20wIBcN%0AMTQwNzIxMDMyMzQ3WhgPMjE1MTA2MTMwMzIzNDdaMIGXMQswCQYDVQQGEwJVUzET%0AMBEGA1UECAwKQ2FsaWZvcm5pYTEWMBQGA1UEBwwNU2FuIEZyYW5jaXNjbzESMBAG%0AA1UECgwJT3BlblJlc3R5MRIwEAYDVQQLDAlPcGVuUmVzdHkxETAPBgNVBAMMCHRl%0Ac3QuY29tMSAwHgYJKoZIhvcNAQkBFhFhZ2VudHpoQGdtYWlsLmNvbTCBnzANBgkq%0AhkiG9w0BAQEFAAOBjQAwgYkCgYEA6P18zUvtmaKQK2xePy8ZbFwSyTLw%2BjW6t9eZ%0AaiTec8X3ibN9WemrxHzkTRikxP3cAQoITRuZiQvF4Q7DO6wMkz%2Fb0zwfgX5uedGq%0A047AJP6n%2FmwlDOjGSNomBLoXQzo7tVe60ikEm3ZyDUqnJPJMt3hImO5XSop4MPMu%0AZa9WhFcCAwEAATANBgkqhkiG9w0BAQUFAAOBgQA4OBb9bOyWB1%2F%2F93nSXX1mdENZ%0AIQeyTK0Dd6My76lnZxnZ4hTWrvvd0b17KLDU6JnS2N5ee3ATVkojPidRLWLIhnh5%0A0eXrcKalbO2Ce6nShoFvQCQKXN2Txmq2vO%2FMud2bHAWwJALg%2Bqi1Iih%2FgVYB9sct%0AFLg8zFOzRlYiU%2B6Mmw%3D%3D%0A-----END%20CERTIFICATE-----%0A]]

local tls_fixtures = { http_mock = {
  tls_server_block = [[
    server {
        server_name tls_test_client;
        listen 10121;

        location = /good_client {
            proxy_ssl_certificate /kong/spec-ee/fixtures/good_tls_client.crt;
            proxy_ssl_certificate_key /kong/spec-ee/fixtures/good_tls_client.key;
            proxy_ssl_name example.com;
            # enable send the SNI sent to server
            proxy_ssl_server_name on;
            proxy_set_header Host example.com;

            proxy_pass https://127.0.0.1:9443/get;
        }

        location = /bad_client {
            proxy_ssl_certificate /kong/spec-ee/fixtures/bad_tls_client.crt;
            proxy_ssl_certificate_key /kong/spec-ee/fixtures/bad_tls_client.key;
            proxy_ssl_name example.com;
            proxy_set_header Host example.com;

            proxy_pass https://127.0.0.1:9443/get;
        }

        location = /another {
          proxy_ssl_certificate /kong/spec-ee/fixtures/good_tls_client.crt;
          proxy_ssl_certificate_key /kong/spec-ee/fixtures/good_tls_client.key;
          proxy_ssl_name example.com;
          proxy_set_header Host example.com;

          proxy_pass https://127.0.0.1:9443/anything;
      }

    }
  ]], }
}

for _, strategy in strategies() do
  describe("Plugin: tls plugins (access) [#" .. strategy .. "]", function()
    local proxy_client, proxy_ssl_client, tls_client
    local bp, db
    local service_https, route_https1, route_https2
    local plugin1, plugin2
    local db_strategy = strategy ~= "off" and strategy or nil

    lazy_setup(function()
      bp, db = helpers.get_db_utils(db_strategy, {
        "routes",
        "services",
        "plugins",
      }, { "tls-handshake-modifier", "tls-metadata-headers", })

      service_https = bp.services:insert{
        protocol = "https",
        port     = 443,
        host     = "httpbin.org",
      }

      route_https1 = bp.routes:insert {
        hosts   = { "example.com" },
        service = { id = service_https.id, },
        strip_path = false,
        paths = { "/get"},
      }

      plugin1 = assert(bp.plugins:insert {
        name = "tls-handshake-modifier",
        route = { id = route_https1.id },
      })

      plugin2 = assert(bp.plugins:insert {
        name = "tls-metadata-headers",
        route = { id = route_https1.id },
        config = { inject_client_cert_details = true,
        },
      })

      route_https2 = bp.routes:insert {
        service = { id = service_https.id, },
        hosts   = { "example.com" },
        strip_path = false,
        paths = { "/anything"},
      }

      plugin1 = assert(bp.plugins:insert {
        name = "tls-handshake-modifier",
        route = { id = route_https2.id },
      })

      plugin2 = assert(bp.plugins:insert {
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

      assert(helpers.start_kong({
        database   = db_strategy,
        plugins = "bundled,tls-handshake-modifier,tls-metadata-headers",
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



    describe("valid certificate", function()
      it("returns HTTP 200 on https request if certificate validation passed", function()
        local res = assert(tls_client:send {
          method  = "GET",
          path    = "/good_client",
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal(client_crt_good, json.headers["X-Client-Cert"])
        assert.equal("65", json.headers["X-Client-Cert-Serial"])
        assert.equal("emailAddress=test@test.com,OU=PS,O=Kong,L=Sydney,ST=NSW,C=AU", json.headers["X-Client-Cert-Issuer-Dn"])
        assert.equal("emailAddress=test@test.com,OU=PS,O=Kong,L=Sydney,ST=NSW,C=AU", json.headers["X-Client-Cert-Subject-Dn"])
        assert.equal("88b74971771571c618e6c6215ba4f6ef71ccc2c7", json.headers["X-Client-Cert-Fingerprint"])
      end)

      it("returns HTTP 200 on https request if certificate validation passed - plugin does not validate certificate", function()
        local res = assert(tls_client:send {
          method  = "GET",
          path    = "/bad_client",
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal(client_crt_bad, json.headers["X-Client-Cert"])
        assert.equal("A50E6D5692B796E2", json.headers["X-Client-Cert-Serial"])
        assert.equal("emailAddress=agentzh@gmail.com,CN=test.com,OU=OpenResty,O=OpenResty,L=San Francisco,ST=California,C=US", json.headers["X-Client-Cert-Issuer-Dn"])
        assert.equal("emailAddress=agentzh@gmail.com,CN=test.com,OU=OpenResty,O=OpenResty,L=San Francisco,ST=California,C=US", json.headers["X-Client-Cert-Subject-Dn"])
        assert.equal("f65fe7cb882d10dd0b3acefe5d2153c445bb0910", json.headers["X-Client-Cert-Fingerprint"])
      end)

      it("returns HTTP 200 on http request with custom headers", function()
        local res = assert(tls_client:send {
          method  = "GET",
          path    = "/another",
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal(client_crt_good, json.headers["X-Client-Cert-Custom"])
        assert.equal("65", json.headers["X-Client-Cert-Serial-Custom"])
        assert.equal("emailAddress=test@test.com,OU=PS,O=Kong,L=Sydney,ST=NSW,C=AU", json.headers["X-Client-Cert-Issuer-Dn-Custom"])
        assert.equal("emailAddress=test@test.com,OU=PS,O=Kong,L=Sydney,ST=NSW,C=AU", json.headers["X-Client-Cert-Subject-Dn-Custom"])
        assert.equal("88b74971771571c618e6c6215ba4f6ef71ccc2c7", json.headers["X-Client-Cert-Fingerprint-Custom"])
      end)

    end)


    describe("no certificate", function()

      it("returns HTTP 200 on http request no certificate passed in request", function()
        local res = assert(proxy_ssl_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            host = "example.com",
          }
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.is_nil(json.headers["X-Client-Cert"])
        assert.is_nil(json.headers["X-Client-Cert-Serial"])
        assert.is_nil(json.headers["X-Client-Cert-Issuer-Dn"])
        assert.is_nil(json.headers["X-Client-Cert-Subject-Dn"])
        assert.is_nil(json.headers["X-Client-Cert-Fingerprint"])
      end)

    end)


  end)
end
