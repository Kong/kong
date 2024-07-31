-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local pl_file = require "pl.file"
local cjson   = require "cjson"
local http_mock = require "spec.helpers.http_mock"

local strategies = helpers.all_strategies ~= nil and helpers.all_strategies or helpers.each_strategy

local CA1 = pl_file.read(helpers.get_fixtures_path() .. "/ca1.crt")
local CA2 = pl_file.read(helpers.get_fixtures_path() .. "/ca2.crt")
local Other_CA = pl_file.read("./spec/fixtures/mtls_certs/ca.crt")

local HTTP_SERVER_PORT = helpers.get_available_port()

local base64_encoded_header_value = "MIIDLTCCAhUCCQC8vcesHOs+1DANBgkqhkiG9w0BAQsFADBYMQswCQYDVQQGEwJVUzELMAkGA1UECAwCQ0ExCzAJBgNVBAcMAlNGMQ0wCwYDVQQKDARrb25nMQwwCgYDVQQLDANGVFQxEjAQBgNVBAMMCWtvbmdyb290MTAeFw0yMzExMjgwODQ5MTdaFw0zMzExMjUwODQ5MTdaMFkxCzAJBgNVBAYTAlVTMQswCQYDVQQIDAJDQTELMAkGA1UEBwwCU0YxDTALBgNVBAoMBGtvbmcxDDAKBgNVBAsMA0ZUVDETMBEGA1UEAwwKa29uZ2NsaWVudDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAOF00iFNtMS3Jwp9NoqH3EtMCAD6+ni5SD5zSmeLX2ZwW99FpH0KPBZh68Gf87yVxwiSdcY98ujeFWFNWI9PH5itkBmcasgv96yrz/I4zkeEH6OGlG8NRj3+O+TRDuVKglRM74EUBFVzUuvC1Gs3IpyeW7nF8Thw5ZLySndRuoWDJkmJZ8VylacUlCWLFFuw0NptcRuRFnTvZf5bpsnM29cpGRnm7TFXk+WuuDrRjBPHclpnVkZvy1i5xzwAAjYwvo2AeZJoG1LYzbWb+qzbTBQX5U/waau069sHiraExKu0sAlMZtkSYiHGHeBCqtUsxZtJIU5D4hS5FLwi16pWUg0CAwEAATANBgkqhkiG9w0BAQsFAAOCAQEApbw2MUyi56YjwBjesn+RqCH+cl7xQuintvT6mBj1e6TJv2nYpmn84i/WGa7Aen5/wyLiV3+5xNus0nFejzwIekAb7bl8PzR0uX0TDUA83s1LhOJJBFfkgo1YlN34rMhXFo8LULKZpkcTs6ZJhcL804FgVtFuemq4YHD05AM1mM/CxWbGTHwtPSv4URPiEp6YnfHMpuLoUwdcLAgGnKq5N2focBq2dIQNBxD2UX82lPX77wEpyLSts/mbUmXq3CjNgUUHjLG5w9hdgYvWKI2QPnEktXaPAfo4xh7Vbj9wspKabN1fmdWN2M2ccMZG1w4KvoxdSvcpTvSEfzt4cjKG1w=="

local base64_encoded_header_value2 = "MIIDLTCCAhUCCQD1SkaC3fEdzzANBgkqhkiG9w0BAQsFADBYMQswCQYDVQQGEwJVUzELMAkGA1UECAwCQ0ExCzAJBgNVBAcMAlNGMQ0wCwYDVQQKDARrb25nMQwwCgYDVQQLDANGVFQxEjAQBgNVBAMMCWtvbmdyb290MjAeFw0yMzExMjgwODQ5MTdaFw0zMzExMjUwODQ5MTdaMFkxCzAJBgNVBAYTAlVTMQswCQYDVQQIDAJDQTELMAkGA1UEBwwCU0YxDTALBgNVBAoMBGtvbmcxDDAKBgNVBAsMA0ZUVDETMBEGA1UEAwwKa29uZ2NsaWVudDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBALTuj+hgYx/LaJcZwokfFn6pTi2XpavQFTSV1EU41X+PIOOa+Nkmkat53cAuN5lEeJ4quTqCxFKkG/FI+wKPoAkQ9gndkfWtz4+cChJuB2HszS1JzTyVBbpCoVtcxjUTwcSRKaxB7YLA9YghBq4LOWTTPG5oBfLmXy3zq/IRBafrRQYkxFPYFRWcGP5h1FKW+5DFsr2plBWdl5YTf6wOptZ/FZ99vHAUzukdtrPAtvR8GhWqaCQ7teslhLXBWU/YXiKgdHB79T/exhXCJgviorqzCtiIOFKizXBfoiTtHPIVyDaarw/r0IecAApzk34UtuhjcftCDv0ppZVzFqYBfnkCAwEAATANBgkqhkiG9w0BAQsFAAOCAQEAjSXiSLHLeBj7c0jv/IBFtsvx4Vb8Bj9vZZAQK4NKhtUWFnaCuHq08Moqiw5N0pRsHd605IWYqMiK2tPkdilb6hUX69iEYEkkRh8hGfChmMpo5Jzy4axREbRG5aCjiamNzMnQKQjs+Ud3iIIbTAthxDJOjXhswMLA8pZ9S/FDU1fSi7iplGjf70sl0jeYf/fwXW+vB4rSwek9TGa9cNcsnJtrTTWZIzCC2ZXaSH102BRehMhqMZ4mNrf5nAjcMgJRBJtMbgQyZ0LplNZA0WpJh7NqmHZXJAUK0MShogfyfsqFYFJ0Ye9nTaM07bMdMX953EYFObN4IMIYNsCiGGgRvA=="

for _, strategy in strategies() do
  describe("Plugin: header-cert-auth (cache) [#" .. strategy .. "]", function()
    local mtls_client
    local bp, db
    local service, route
    local ca_cert1, ca_cert2
    local consumer1, consumer2
    local credential1, credential2
    local db_strategy = strategy ~= "off" and strategy or nil
    local mock
    local admin_client

    lazy_setup(function()
      bp, db = helpers.get_db_utils(db_strategy, {
        "routes",
        "services",
        "plugins",
        "consumers",
        "ca_certificates",
        "header_cert_auth_credentials",
      }, { "header-cert-auth", })

      ca_cert1 = assert(db.ca_certificates:insert({
        cert = CA1,
      }))

      ca_cert2 = assert(db.ca_certificates:insert({
        cert = CA2,
      }))

      consumer1 = bp.consumers:insert {
        username = "kongclient1"
      }

      consumer2 = bp.consumers:insert {
        username = "kongclient2"
      }

      credential1 = assert(db.header_cert_auth_credentials:insert {
        consumer = { id = consumer1.id },
        subject_name = "kongclient",
        ca_certificate = { id = ca_cert1.id },
      })

      credential2 = assert(db.header_cert_auth_credentials:insert {
        consumer = { id = consumer2.id },
        subject_name = "kongclient",
        ca_certificate = { id = ca_cert2.id },
      })

      service = bp.services:insert{
        protocol = "https",
        port     = helpers.mock_upstream_ssl_port,
        host     = helpers.mock_upstream_ssl_host,
      }

      route = bp.routes:insert {
        hosts   = { "example.com" },
        service = { id = service.id, },
      }

      assert(bp.plugins:insert {
        name = "header-cert-auth",
        route = { id = route.id },
        config = {
          ca_certificates = { ca_cert1.id, ca_cert2.id},
          revocation_check_mode = "SKIP", certificate_header_name = "ssl-client-cert", certificate_header_format = "base64_encoded", secure_source = false,
        },
      })

      local format = [[
      proxy_ssl_name example.com;
      proxy_ssl_server_name on;
      proxy_set_header Host example.com;
      proxy_pass https://127.0.0.1:9443/get;
      ]]
      -- client1 and client2 have the same CN but are issued by different CAs
      mock = http_mock.new(HTTP_SERVER_PORT, {
        ["/client1"] = {
          directives = format,
        },
        ["/client2"] = {
          directives = format,
        },
      }, {
        hostname = "mtls_test_client",
      })
      assert(mock:start())

      assert(helpers.start_kong({
        database   = db_strategy,
        plugins = "bundled,header-cert-auth",
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
      mock:stop()
    end)

    before_each(function()
      admin_client = assert(helpers.admin_client())
      mtls_client = assert(mock:get_client())
    end)

    after_each(function()
      if admin_client then
        admin_client:close()
      end

      if mtls_client then
        mtls_client:close()
      end
      mock.client = nil
    end)

    it("match the correct consumer via credential", function()
      local res = assert(mtls_client:send {
        method  = "GET",
        path    = "/client1",
        headers = {
          ["ssl-client-cert"] = base64_encoded_header_value,
        },
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.equal("kongclient1", json.headers["x-consumer-username"])
      assert.equal(consumer1.id, json.headers["x-consumer-id"])

      local res = assert(mtls_client:send {
        method  = "GET",
        path    = "/client2",
        headers = {
          ["ssl-client-cert"] = base64_encoded_header_value2,
        }
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.equal("kongclient2", json.headers["x-consumer-username"])
      assert.equal(consumer2.id, json.headers["x-consumer-id"])
    end)

    it("still match the correct consumer via credential after the CAs updated", function()
      -- switch the ca certificates so that
      -- ca_cert1.id binds to CA2, ca_cert2.id binds to CA1
      -- We first update it to Other_CA to avoid unique field violation as the `cert_digest`
      -- field of `ca_certificates` is a unique field. Thus we use Other_CA as a transition.
      local res = assert(admin_client:send({
        method  = "PATCH",
        path    = "/ca_certificates/" .. ca_cert1.id,
        body    = {
          cert = Other_CA,
        },
        headers = {
          ["Content-Type"] = "application/json"
        },
      }))
      assert.res_status(200, res)

      local res = assert(admin_client:send({
        method  = "PATCH",
        path    = "/ca_certificates/" .. ca_cert2.id,
        body    = {
          cert = CA1,
        },
        headers = {
          ["Content-Type"] = "application/json"
        },
      }))
      assert.res_status(200, res)

      local res = assert(admin_client:send({
        method  = "PATCH",
        path    = "/ca_certificates/" .. ca_cert1.id,
        body    = {
          cert = CA2,
        },
        headers = {
          ["Content-Type"] = "application/json"
        },
      }))
      assert.res_status(200, res)

      -- need update the credentials as well after updating the ca certificates
      local res = assert(admin_client:send {
        method  = "DELETE",
        path    = "/consumers/kongclient1/header-cert-auth/" .. credential1.id,
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      assert.res_status(204, res)

      local res = assert(admin_client:send {
        method  = "DELETE",
        path    = "/consumers/kongclient2/header-cert-auth/" .. credential2.id,
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      assert.res_status(204, res)

      local res = assert(admin_client:send {
        method  = "POST",
        path    = "/consumers/kongclient1/header-cert-auth/",
        body    = {
          id = credential1.id,
          subject_name = "kongclient",
          ca_certificate = { id = ca_cert2.id },
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      assert.res_status(201, res)

      local res = assert(admin_client:send {
        method  = "POST",
        path    = "/consumers/kongclient2/header-cert-auth/",
        body    = {
          id = credential2.id,
          subject_name = "kongclient",
          ca_certificate = { id = ca_cert1.id },
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      assert.res_status(201, res)

      -- switch back
      finally(function()
        local res = assert(admin_client:send({
          method  = "PATCH",
          path    = "/ca_certificates/" .. ca_cert1.id,
          body    = {
            cert = Other_CA,
          },
          headers = {
            ["Content-Type"] = "application/json"
          },
        }))
        assert.res_status(200, res)

        local res = assert(admin_client:send({
          method  = "PATCH",
          path    = "/ca_certificates/" .. ca_cert2.id,
          body    = {
            cert = CA2,
          },
          headers = {
            ["Content-Type"] = "application/json"
          },
        }))
        assert.res_status(200, res)

        local res = assert(admin_client:send({
          method  = "PATCH",
          path    = "/ca_certificates/" .. ca_cert1.id,
          body    = {
            cert = CA1,
          },
          headers = {
            ["Content-Type"] = "application/json"
          },
        }))
        assert.res_status(200, res)

        local res = assert(admin_client:send {
          method  = "DELETE",
          path    = "/consumers/kongclient1/header-cert-auth/" .. credential1.id,
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        assert.res_status(204, res)

        local res = assert(admin_client:send {
          method  = "DELETE",
          path    = "/consumers/kongclient2/header-cert-auth/" .. credential2.id,
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        assert.res_status(204, res)

        local res = assert(admin_client:send {
          method  = "POST",
          path    = "/consumers/kongclient1/header-cert-auth/",
          body    = {
            id = credential1.id,
            subject_name = "kongclient",
            ca_certificate = { id = ca_cert1.id },
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        assert.res_status(201, res)

        local res = assert(admin_client:send {
          method  = "POST",
          path    = "/consumers/kongclient2/header-cert-auth/",
          body    = {
            id = credential2.id,
            subject_name = "kongclient",
            ca_certificate = { id = ca_cert2.id },
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        assert.res_status(201, res)
      end)

      assert.eventually(function()
        local res = assert(mtls_client:send {
          method  = "GET",
          path    = "/client1",
          headers = {
            ["ssl-client-cert"] = base64_encoded_header_value,
          },
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("kongclient1", json.headers["x-consumer-username"])
        assert.equal(consumer1.id, json.headers["x-consumer-id"])

        local res = assert(mtls_client:send {
          method  = "GET",
          path    = "/client2",
          headers = {
            ["ssl-client-cert"] = base64_encoded_header_value2,
          }
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("kongclient2", json.headers["x-consumer-username"])
        assert.equal(consumer2.id, json.headers["x-consumer-id"])
      end).with_timeout(3)
          .has_no_error("match the correct consumer")
    end)
  end)
end
