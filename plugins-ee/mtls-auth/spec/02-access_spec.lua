-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local pl_file = require "pl.file"
local cjson   = require "cjson"
local utils   = require "kong.tools.utils"

local strategies = helpers.all_strategies ~= nil and helpers.all_strategies or helpers.each_strategy

local LOG_PATH = "/tmp/request.log." .. tostring(ngx.worker.pid())

local function get_log(res)
  local id = assert.response(res).has.header("x-request-id")

  local entry
  helpers.wait_until(function()
    local fh = io.open(LOG_PATH, "r")
    if fh then
      for line in fh:lines() do
        if line:find(id, nil, true) then
          entry = cjson.decode(line)
          return true
        end
      end
    end
  end, 5, 0.25)

  return entry
end



local CA = [[
-----BEGIN CERTIFICATE-----
MIIFoTCCA4mgAwIBAgIUQDBLwIychoRbVRO44IzBBk9R4oYwDQYJKoZIhvcNAQEL
BQAwWDELMAkGA1UEBhMCVVMxEzARBgNVBAgMCkNhbGlmb3JuaWExFTATBgNVBAoM
DEtvbmcgVGVzdGluZzEdMBsGA1UEAwwUS29uZyBUZXN0aW5nIFJvb3QgQ0EwHhcN
MTkwNTAyMTkzNDQyWhcNMzkwNDI3MTkzNDQyWjBYMQswCQYDVQQGEwJVUzETMBEG
A1UECAwKQ2FsaWZvcm5pYTEVMBMGA1UECgwMS29uZyBUZXN0aW5nMR0wGwYDVQQD
DBRLb25nIFRlc3RpbmcgUm9vdCBDQTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCC
AgoCggIBAMp6IggUp3aSNRbLAac8oOkrbUnFuxtlKGYgg8vfA2UU71qTktigdwO6
Kod0/M+daO3RDqJJXQL2rD14NDO3MaextICanoQSEe+nYyMFUIk+QplXLD3fbshU
nHoJcMS2w0x4cm1os4ebxR2Evndo6luz39ivcjau+BL+9iBAYL1g6+eGOjcSy7ft
1nAMvbxcQ7dmbAH2KP6OmF8cok+eQWVqXEjqtVx5GDMDlj1BjX6Kulmh/vhNi3Hr
NEi+kPrw/YtRgnqnN0sv3NnAyKnantxy7w0TDicFjiBsSIhjB5aUfWYErBR+Nj/m
uumwc/kRJcHWklqDzxrZKCIyOyWcE5Dyjjr46cnF8HxhYwgZcwkmgTtaXOLpBMlo
XUTgOQrWpm9HYg2vOJMMA/ZPUJ2tJ34/4RgiA00EJ5xG8r24suZmT775l+XFLFzp
Ihxvs3BMbrWsXlcZkI5neNk7Q/1jLoBhWeTYjMpUS7bJ/49YVGQZFs3xu2IcLqeD
5WsB1i+EqBAI0jm4vWEynsyX+kS2BqAiDtCsS6WYT2q00DTeP5eIHh/vHsm75jJ+
yUEb1xFxGnNevLKNTcHUeXxPUnowdC6wqFnaJm7l09qVGDom7tLX9i6MCojgpAP0
hMpBxzh8jLxHh+zZQdiORSFdYxNnlnWwbic2GUJruiQVLuhpseenAgMBAAGjYzBh
MB0GA1UdDgQWBBQHT/IIheEC2kdBxI/TfGqUxWJw9zAfBgNVHSMEGDAWgBQHT/II
heEC2kdBxI/TfGqUxWJw9zAPBgNVHRMBAf8EBTADAQH/MA4GA1UdDwEB/wQEAwIB
hjANBgkqhkiG9w0BAQsFAAOCAgEAqXZjy4EltJCRtBmN0ohAHPWqH4ZJQCI2HrM3
wHB6c4oPWcJ+M2PfmYPUJo9VMjvn4S3sZuAysyoHduvRdGDnElW4wglL1xxpoUOx
FqoZUoYWV8hDFmUTWM5b4CtJxOPdTAd8VgypulM3iUEzBQrjR6tnMOdkiFMOmVag
0/Nnr+Tcfk/crMCx3xsVnisYjJoQBFBH4UY+gWE/V/MS1Sya4/qTbuuCUq+Qym5P
r8TkWAJlg7iVVLbZ2j94VUdpiQPWJEGMtJck/NEmOTruhhQlT7c1u/lqXCGj7uci
LmhLsBVmdtWT9AWS8Rl7Qo5GXbjxKIaP3IM9axhDLm8WHwPRLx7DuIFEc+OBxJhz
wkr0g0yLS0AMZpaC6UGbWX01ed10U01mQ/qPU5uZiB0GvruwsYWZsyL1QXUeqLz3
/KKrx3XsXjtBu3ZG4LAnwuxfeZCNw9ofg8CqF9c20ko+7tZAv6DCu9UL+2oZnEyQ
CboRDwpnAlQ7qJVSp2xMgunO3xxVMlhD5LZpEJz1lRT0nQV3uuLpMYNM4FS9OW/X
MZSzwHhDdCTDWtc/iRszimOnYYV8Y0ubJcb59uhwcsHmdfnwL9DVO6X5xyzb8wsf
wWaPbub8SN2jKnT0g6ZWuca4VwEo1fRaBkzSZDqXwhkBDWP8UBqLXMXWHdZaT8NK
0NEO74c=
-----END CERTIFICATE-----
]]

local other_CA = [[
-----BEGIN CERTIFICATE-----
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
-----END CERTIFICATE-----
]]

local intermediate_CA = [[
-----BEGIN CERTIFICATE-----
MIICsjCCAZqgAwIBAgICEAAwDQYJKoZIhvcNAQELBQAwEjEQMA4GA1UEAwwHUm9v
dC1jYTAgFw0yMjEwMTkxNDQzNDVaGA8yMTIyMDkyNTE0NDM0NVowEjEQMA4GA1UE
AwwHSW50ZXJtLjCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAJ6uSUl/
FBmIzbq+UD1HROTiJ+ftJa0KwgEg0JwsKbd+9Ne92MlNNzG9glO8eWlIRsZTlkz9
DxDXFJIMRqP7Fn9ZPeOAi2/VH+xIctBaIRcF/E/RwwrxnKOpaJvXOFudUg+YIPjP
H59Wof4PQMU9ijArc6KNRuVlMDQlC9MSaX9lhUzO4Nk8IT9rmLi0Z5O0KK+mFkWv
uN2uL9TqEumvea+Y5JKDitJxwFmGjGB18GIoKT0fOZVio/xyMuv7t7PybzE87wsd
bACkqO48pwwIMC/TCpeWaxZ1+sSoT3zZXdD+tua/MLIM2ubrmBZFJKYP8mxOqUgK
D29gWpcuZAIlrnUCAwEAAaMQMA4wDAYDVR0TBAUwAwEB/zANBgkqhkiG9w0BAQsF
AAOCAQEAVHSP6GPjLmvAuyOWncRKgBWJaP17UF0lZYIkJDW258nTqmQD2FMlNrp5
l/r/5pkl45BOsf3kxsqjZNx/1QuyLfeb6R7BIWMSzdFvNuzYjqyfQHADxTuq6cCA
3/eZ+fQA8da6LSLeIH+zKftNjDLjqAEVziID4ZQd1U2tHTMgFwNjlAH/ydAtqmdN
HkWpdejvtYnUSWQrcJZN/C/vFGukNly06LFRd71iTHyPWg+8nybJXFOMfrW6qfMi
SRAb/oQJaOMxXNrpXEQv/vbO8BK3LGmq2Bm2WIVFUhDKEdOqSvmeWoa8eM0bKT39
fs6geD+F2d4dQAUspVmBp1z6nlb/FA==
-----END CERTIFICATE-----
]]

local mtls_fixtures = { http_mock = {
  mtls_server_block = [[
    server {
        server_name mtls_test_client;
        listen 10121;

        location = /example_client {
            # Combined cert, contains client first and intermediate second
            proxy_ssl_certificate ../spec/fixtures/client_example.com.crt;
            proxy_ssl_certificate_key ../spec/fixtures/client_example.com.key;
            proxy_ssl_name example.com;
            # enable send the SNI sent to server
            proxy_ssl_server_name on;
            proxy_set_header Host example.com;

            proxy_pass https://127.0.0.1:9443/get;
        }

        location = /bad_client {
            proxy_ssl_certificate ../spec/fixtures/bad_client.crt;
            proxy_ssl_certificate_key ../spec/fixtures/bad_client.key;
            proxy_ssl_name example.com;
            proxy_set_header Host example.com;

            proxy_pass https://127.0.0.1:9443/get;
        }

        location = /no_san_client {
            proxy_ssl_certificate ../spec/fixtures/no_san.crt;
            proxy_ssl_certificate_key ../spec/fixtures/no_san.key;
            proxy_ssl_name example.com;
            proxy_set_header Host example.com;

            proxy_pass https://127.0.0.1:9443/get;
        }

        location = /intermediate_example_client {
          proxy_ssl_certificate ../spec/fixtures/intermediate_client_example.com.crt;
          proxy_ssl_certificate_key ../spec/fixtures/intermediate_client_example.com.key;
          proxy_ssl_name example.com;
          proxy_set_header Host example.com;

          proxy_pass https://127.0.0.1:9443/get;
      }
    }
  ]], }
}

-- FIXME: in case of FIPS build, the nginx refuses to send invalid client certificate to upstream
-- thus we skip the test for now
local bad_client_tests
if helpers.is_fips_build() then
  bad_client_tests = pending
else
  bad_client_tests = it
end

for _, strategy in strategies() do
  describe("Plugin: mtls-auth (access) [#" .. strategy .. "]", function()
    local proxy_client, admin_client, proxy_ssl_client, mtls_client
    local bp, db
    local anonymous_user, consumer, customized_consumer, service, route
    local plugin
    local ca_cert, other_ca_cert
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

      anonymous_user = bp.consumers:insert {
        username = "anonymous@example.com",
      }

      consumer = bp.consumers:insert {
        username = "foo@example.com"
      }

      customized_consumer = bp.consumers:insert {
        username = "customized@example.com"
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

      ca_cert = assert(db.ca_certificates:insert({
        cert = CA,
      }))

      other_ca_cert = assert(db.ca_certificates:insert({
        cert = other_CA,
      }))

      plugin = assert(bp.plugins:insert {
        name = "mtls-auth",
        route = { id = route.id },
        config = { ca_certificates = { ca_cert.id, }, },
      })

      bp.plugins:insert({
        name = "pre-function",
        config = {
          header_filter = {[[
            ngx.header["x-request-id"] = ngx.var.request_id
          ]]},
        },
      })

      bp.plugins:insert {
        route = { id = route.id },
        name     = "file-log",
        config   = {
          reopen = true,
          path   = LOG_PATH,
          custom_fields_by_lua = {
            request_id = [[return ngx.var.request_id]],
          }
        },
      }

      assert(helpers.start_kong({
        database   = db_strategy,
        plugins = "mtls-auth,file-log,pre-function",
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

    describe("Unauthorized", function()
      it("returns HTTP 401 on non-https request", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            ["Host"] = "example.com"
          }
        })
        local body = assert.res_status(401, res)
        local json = cjson.decode(body)
        assert.same({ message = "No required TLS certificate was sent" }, json)
      end)

      it("returns HTTP 401 on https request if mutual TLS was not completed", function()
        local res = assert(proxy_ssl_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            ["Host"] = "example.com"
          }
        })
        local body = assert.res_status(401, res)
        local json = cjson.decode(body)
        assert.same({ message = "No required TLS certificate was sent" }, json)
      end)

      bad_client_tests("returns HTTP 401 on https request if certificate validation failed", function()
        local res = assert(mtls_client:send {
          method  = "GET",
          path    = "/bad_client",
        })
        local body = assert.res_status(401, res)
        local json = cjson.decode(body)

        assert.same({ message = "TLS certificate failed verification" }, json)
      end)
    end)

    describe("valid certificate", function()
      it("returns HTTP 200 on https request if certificate validation passed", function()
        local res = assert(mtls_client:send {
          method  = "GET",
          path    = "/example_client",
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("foo@example.com", json.headers["x-consumer-username"])
        assert.equal(consumer.id, json.headers["x-consumer-id"])
        assert.equal("consumer-id-2", json.headers["x-consumer-custom-id"])
      end)

      it("returns HTTP 401 on https request if certificate validation passed", function()
        local res = assert(mtls_client:send {
          method  = "GET",
          path    = "/no_san_client",
        })
        assert.res_status(401, res)
      end)

      it("overrides client_verify field in basic log serialize so it contains sensible content #4626", function()
        local res = assert(mtls_client:send {
          method  = "GET",
          path    = "/example_client",
        })
        assert.res_status(200, res)

        local log_message = get_log(res)
        assert.equal("SUCCESS", log_message.request.tls.client_verify)
      end)
    end)

    describe("custom credential", function()
      local plugin_id
      lazy_setup(function()
        local res = assert(admin_client:send({
          method  = "POST",
          path    = "/consumers/" .. customized_consumer.id  .. "/mtls-auth",
          body    = {
            subject_name   = "foo@example.com",
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        }))
        local body = assert.res_status(201, res)
        local json = cjson.decode(body)
        plugin_id = json.id
      end)
      lazy_teardown(function()
        local res = assert(admin_client:send({
          method  = "DELETE",
          path    = "/consumers/" .. customized_consumer.id  .. "/mtls-auth/" .. plugin_id,
        }))
        assert.res_status(204, res)
      end)

      it("overrides auto-matching", function()
        local res = assert(mtls_client:send {
          method  = "GET",
          path    = "/example_client",
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("customized@example.com", json.headers["x-consumer-username"])
        assert.equal(customized_consumer.id, json.headers["x-consumer-id"])
        assert.equal("consumer-id-3", json.headers["x-consumer-custom-id"])
      end)
    end)

    describe("custom credential with ca_certificate", function()
      local plugin_id
      lazy_setup(function()
        local res = assert(admin_client:send({
          method  = "POST",
          path    = "/consumers/" .. customized_consumer.id  .. "/mtls-auth",
          body    = {
            subject_name   = "foo@example.com",
            ca_certificate = { id = ca_cert.id },
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        }))
        local body = assert.res_status(201, res)
        local json = cjson.decode(body)
        plugin_id = json.id
      end)
      lazy_teardown(function()
        local res = assert(admin_client:send({
          method  = "DELETE",
          path    = "/consumers/" .. customized_consumer.id  .. "/mtls-auth/" .. plugin_id,
        }))
        assert.res_status(204, res)
      end)

      it("overrides auto-matching", function()
        local res = assert(mtls_client:send {
          method  = "GET",
          path    = "/example_client",
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("customized@example.com", json.headers["x-consumer-username"])
        assert.equal(customized_consumer.id, json.headers["x-consumer-id"])
        assert.equal("consumer-id-3", json.headers["x-consumer-custom-id"])
      end)
    end)

    describe("custom credential with invalid ca_certificate", function()
      local plugin_id
      lazy_setup(function()
        local res = assert(admin_client:send({
          method  = "POST",
          path    = "/consumers/" .. customized_consumer.id  .. "/mtls-auth",
          body    = {
            subject_name   = "foo@example.com",
            ca_certificate = { id = other_ca_cert.id },
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        }))
        local body = assert.res_status(201, res)
        local json = cjson.decode(body)
        plugin_id = json.id
      end)
      lazy_teardown(function()
        local res = assert(admin_client:send({
          method  = "DELETE",
          path    = "/consumers/" .. customized_consumer.id  .. "/mtls-auth/" .. plugin_id,
        }))
        assert.res_status(204, res)
      end)

      -- Falls through to step 2 of https://docs.konghq.com/hub/kong-inc/mtls-auth/#matching-behaviors
      it("falls back to auto-matching", function()
        local res = assert(mtls_client:send {
          method  = "GET",
          path    = "/example_client",
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("foo@example.com", json.headers["x-consumer-username"])
        assert.equal(consumer.id, json.headers["x-consumer-id"])
        assert.equal("consumer-id-2", json.headers["x-consumer-custom-id"])
      end)
    end)

    describe("skip consumer lookup with valid certificate", function()
      lazy_setup(function()
        local res = assert(admin_client:send({
          method  = "PATCH",
          path    = "/plugins/" .. plugin.id,
          body    = {
            config = { skip_consumer_lookup = true, },
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        }))
        assert.res_status(200, res)
      end)

      lazy_teardown(function()
        local res = assert(admin_client:send({
          method  = "PATCH",
          path    = "/plugins/" .. plugin.id,
          body    = {
            config = { skip_consumer_lookup = false, },
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        }))
        assert.res_status(200, res)
      end)

      it("returns HTTP 200 on https request if certificate validation passed", function()
        assert.eventually(function()
          local res = assert(mtls_client:send {
            method  = "GET",
            path    = "/example_client",
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.is_nil(json.headers["x-consumer-username"])
          assert.is_nil(json.headers["x-consumer-id"])
          assert.is_nil(json.headers["x-consumer-custom-id"])
          assert.not_nil(json.headers["x-client-cert-san"])
          assert.not_nil(json.headers["x-client-cert-dn"])
        end).with_timeout(3)
            .has_no_error("Invalid response code")
      end)

      bad_client_tests("returns HTTP 401 on https request if certificate validation failed", function()
        local res = assert(mtls_client:send {
          method  = "GET",
          path    = "/bad_client",
        })
        assert.res_status(401, res)
      end)
    end)

    describe("use skip_consumer_lookup with authenticated_group_by", function()
      lazy_setup(function()
        local res = assert(admin_client:send({
          method  = "PATCH",
          path    = "/plugins/" .. plugin.id,
          body    = {
            config = {
              skip_consumer_lookup = true,
              authenticated_group_by = ngx.null,
            },
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        }))
        assert.res_status(200, res)
      end)
      lazy_teardown(function()
        local res = assert(admin_client:send({
          method  = "PATCH",
          path    = "/plugins/" .. plugin.id,
          body    = {
            config = {
              skip_consumer_lookup = false,
              authenticated_group_by = "CN",
            },
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        }))
        assert.res_status(200, res)
      end)
      it("doesn't fail when authenticated_group_by = null", function()
        local res = assert(mtls_client:send {
          method  = "GET",
          path    = "/example_client",
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.is_nil(json.headers["x-consumer-username"])
        assert.is_nil(json.headers["x-consumer-id"])
        assert.is_nil(json.headers["x-consumer-custom-id"])
        assert.not_nil(json.headers["x-client-cert-san"])
        assert.not_nil(json.headers["x-client-cert-dn"])
      end)
    end)

    describe("config.anonymous", function()
      lazy_setup(function()
        local res = assert(admin_client:send({
          method  = "PATCH",
          path    = "/plugins/" .. plugin.id,
          body    = {
            config = { anonymous = anonymous_user.id, },
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        }))
        assert.res_status(200, res)
      end)
      lazy_teardown(function()
        local res = assert(admin_client:send({
          method  = "PATCH",
          path    = "/plugins/" .. plugin.id,
          body    = {
            config = { anonymous = nil, },
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        }))
        assert.res_status(200, res)
      end)

      it("works with right credentials and anonymous", function()
        local res = assert(mtls_client:send {
          method  = "GET",
          path    = "/example_client",
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("foo@example.com", json.headers["x-consumer-username"])
        assert.equal(consumer.id, json.headers["x-consumer-id"])
        assert.equal("consumer-id-2", json.headers["x-consumer-custom-id"])
        assert.is_nil(json.headers["x-anonymous-consumer"])
      end)

      bad_client_tests("works with wrong credentials and anonymous", function()
        local res = assert(mtls_client:send {
          method  = "GET",
          path    = "/bad_client",
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("anonymous@example.com", json.headers["x-consumer-username"])
        assert.equal(anonymous_user.id, json.headers["x-consumer-id"])
        assert.equal("consumer-id-1", json.headers["x-consumer-custom-id"])
        assert.equal("true", json.headers["x-anonymous-consumer"])
      end)

      bad_client_tests("logging with wrong credentials and anonymous", function()
        local res = assert(mtls_client:send {
          method  = "GET",
          path    = "/bad_client",
        })
        assert.res_status(200, res)

        local log_message = get_log(res)
        assert.equal("FAILED:self-signed certificate", log_message.request.tls.client_verify)
      end)

      it("works with http (no mTLS handshake)", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            ["Host"] = "example.com"
          }
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("anonymous@example.com", json.headers["x-consumer-username"])
        assert.equal(anonymous_user.id, json.headers["x-consumer-id"])
        assert.equal("consumer-id-1", json.headers["x-consumer-custom-id"])
        assert.equal("true", json.headers["x-anonymous-consumer"])
      end)

      it("logging with https (no mTLS handshake)", function()
        local res = assert(proxy_ssl_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            ["Host"] = "example.com"
          }
        })
        assert.res_status(200, res)

        local log_message = get_log(res)
        assert.equal("NONE", log_message.request.tls.client_verify)
      end)


      it("errors when anonymous user doesn't exist", function()
        local res = assert(admin_client:send({
          method  = "PATCH",
          path    = "/plugins/" .. plugin.id,
          body    = {
            config = { anonymous = "00000000-0000-0000-0000-000000000000", },
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        }))
        assert.res_status(200, res)

        assert.eventually(function()
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/get",
            headers = {
              ["Host"] = "example.com"
            }
          })
          assert.res_status(500, res)
        end).with_timeout(3)
            .has_no_error("Invalid response code")
      end)
    end)

    describe("errors", function()
      lazy_setup(function()
        -- Here we truncate the ca_certificates table, simulating a scenario where
        -- the ca_certificate referenced does not exist in the db
        db:truncate("ca_certificates")
        local res = assert(admin_client:send({
          method  = "DELETE",
          path    = "/cache",
          headers = {
            ["Content-Type"] = "application/json"
          }
        }))
        assert.res_status(204, res)
      end)

      it("errors when CA doesn't exist", function()
        local uuid = utils.uuid()
        assert(admin_client:send({
          method  = "PATCH",
          path    = "/plugins/" .. plugin.id,
          body    = {
            config = { ca_certificates = { uuid, }, },
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        }))

        local res = assert(mtls_client:send {
          method  = "GET",
          path    = "/example_client",
        })
        -- expected worker crash
        assert.res_status(500, res)
        local err_log = pl_file.read(helpers.test_conf.nginx_err_logs)
        assert.matches("CA Certificate '" .. uuid .. "' does not exist", err_log, nil, true)

      end)
    end)
  end)

  describe("Plugin: mtls-auth (access) with filter [#" .. strategy .. "]", function()
    local proxy_client, admin_client, mtls_client
    local proxy_ssl_client_foo, proxy_ssl_client_bar, proxy_ssl_client_alice
    local bp, db
    local service
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
        "workspaces",
      }, { "mtls-auth", })

      bp.consumers:insert {
        username = "foo@example.com"
      }

      bp.consumers:insert {
        username = "customized@example.com"
      }

      service = bp.services:insert{
        protocol = "https",
        port     = helpers.mock_upstream_ssl_port,
        host     = helpers.mock_upstream_ssl_host,
      }

      assert(bp.routes:insert {
        hosts   = { "foo.com" },
        service = { id = service.id, },
        snis = { "foo.com" },
      })

      assert(bp.routes:insert {
        hosts   = { "bar.com" },
        service = { id = service.id, },
        snis = { "bar.com" },
      })

      ca_cert = assert(db.ca_certificates:insert({
        cert = CA,
      }))

      assert(bp.plugins:insert {
        name = "mtls-auth",
        config = { ca_certificates = { ca_cert.id, }, },
        service = { id = service.id, },
      })

      local service2 = bp.services:insert{
        protocol = "https",
        port     = helpers.mock_upstream_ssl_port,
        host     = helpers.mock_upstream_ssl_host,
      }

      assert(bp.routes:insert {
        hosts   = { "alice.com" },
        service = { id = service2.id, },
        snis = { "alice.com" },
      })

      assert(helpers.start_kong({
        database   = db_strategy,
        plugins = "bundled,mtls-auth",
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }, nil, nil, mtls_fixtures))

      proxy_client = helpers.proxy_client()
      proxy_ssl_client_foo = helpers.proxy_ssl_client(nil, "foo.com")
      proxy_ssl_client_bar = helpers.proxy_ssl_client(nil, "bar.com")
      proxy_ssl_client_alice = helpers.proxy_ssl_client(nil, "alice.com")
      mtls_client = helpers.http_client("127.0.0.1", 10121)
      admin_client = helpers.admin_client()
    end)

    lazy_teardown(function()
      if proxy_client then
        proxy_client:close()
      end

      if proxy_ssl_client_foo then
        proxy_ssl_client_foo:close()
      end

      if proxy_ssl_client_bar then
        proxy_ssl_client_bar:close()
      end

      if proxy_ssl_client_alice then
        proxy_ssl_client_alice:close()
      end

      if mtls_client then
        mtls_client:close()
      end

      if admin_client then
        admin_client:close()
      end

      helpers.stop_kong(nil, true)
    end)

    describe("request certs for specific routes", function()
      it("request cert for host foo", function()
        local res = assert(proxy_ssl_client_foo:send {
          method  = "GET",
          path    = "/get",
          headers = {
            ["Host"] = "foo.com"
          }
        })
        local body = assert.res_status(401, res)
        local json = cjson.decode(body)
        assert.same({ message = "No required TLS certificate was sent" }, json)
      end)

      it("request cert for host bar", function()
        local res = assert(proxy_ssl_client_bar:send {
          method  = "GET",
          path    = "/get",
          headers = {
            ["Host"] = "bar.com"
          }
        })
        local body = assert.res_status(401, res)
        local json = cjson.decode(body)
        assert.same({ message = "No required TLS certificate was sent" }, json)
      end)

      it("do not request cert for host alice", function()
        local res = assert(proxy_ssl_client_alice:send {
          method  = "GET",
          path    = "/get",
          headers = {
            ["Host"] = "alice.com"
          }
        })
        assert.res_status(200, res)
      end)

      it("request cert for specific request", function()
        local res = assert(admin_client:send {
          method  = "GET",
          path    = "/cache/mtls-auth:cert_enabled_snis",
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.is.truthy(json["foo.com"])
        assert.is.truthy(json["bar.com"])
        assert.is_nil(json["*"])

      end)
    end)
    describe("request certs for all routes", function()
      it("request cert for all request", function()
        local res = assert(admin_client:send {
          method  = "POST",
          path    = "/routes",
          body = {
            hosts   = { "all.com" },
            service = { id = service.id, },
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        assert.res_status(201, res)

        helpers.wait_until(function()
          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/cache/mtls-auth:cert_enabled_snis",
          })
          res:read_body()
          return res.status == 404
        end)

        local res = assert(proxy_ssl_client_bar:send {
          method  = "GET",
          path    = "/get",
          headers = {
            ["Host"] = "all.com"
          }
        })
        local body = assert.res_status(401, res)
        local json = cjson.decode(body)
        assert.same({ message = "No required TLS certificate was sent" }, json)

        --helpers.wait_until(function()
        --  local client = helpers.admin_client()
        --  local res = assert(client:send {
        --    method  = "GET",
        --    path    = "/cache/mtls-auth:cert_enabled_snis",
        --  })
        --  res:read_body()
        --  if res.status == 404 then
        --    return false
        --  end
        --
        --  local raw = assert.res_status(200, res)
        --  local body = cjson.decode(raw)
        --  if body["*"] then
        --    return true
        --  end
        --end, 10)

      end)
    end)
  end)
  describe("Plugin: mtls-auth (access) with filter [#" .. strategy .. "] non default workspace", function()
    local proxy_client, admin_client, mtls_client
    local proxy_ssl_client_foo, proxy_ssl_client_example
    local bp, db
    local service, workspace, consumer
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
        "workspaces",
      }, { "mtls-auth", })

      workspace = assert(db.workspaces:insert({ name = "test_ws_" .. utils.uuid()}))

      consumer = bp.consumers:insert({
        username = "foo@example.com"
      },  { workspace = workspace.id })

      service = bp.services:insert({
        protocol = "https",
        port     = helpers.mock_upstream_ssl_port,
        host     = helpers.mock_upstream_ssl_host,
      }, { workspace = workspace.id })

      assert(bp.routes:insert({
        snis   = { "example.com" },
        service = { id = service.id, },
        paths = { "/get" },
        strip_path = false,
      }, { workspace = workspace.id }))

      assert(bp.routes:insert({
        service = { id = service.id, },
        paths = { "/anotherroute" },
      }, { workspace = workspace.id }))

      ca_cert = assert(db.ca_certificates:insert({
        cert = CA,
      }, { workspace = workspace.id }))

      assert(bp.plugins:insert({
        name = "mtls-auth",
        config = { ca_certificates = { ca_cert.id, }, },
        service = { id = service.id, },
      }, { workspace = workspace.id }))

      -- in default workspace:
      local service2 = bp.services:insert({
        protocol = "https",
        port     = helpers.mock_upstream_ssl_port,
        host     = helpers.mock_upstream_ssl_host,
      })

      assert(bp.routes:insert({
        service = { id = service2.id, },
        paths = { "/default" },
      }))

      assert(helpers.start_kong({
        database   = db_strategy,
        plugins = "bundled,mtls-auth",
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }, nil, nil, mtls_fixtures))

      proxy_client = helpers.proxy_client()
      proxy_ssl_client_foo = helpers.proxy_ssl_client(nil, "foo.com")
      proxy_ssl_client_example = helpers.proxy_ssl_client(nil, "example.com")
      mtls_client = helpers.http_client("127.0.0.1", 10121)
      admin_client = helpers.admin_client()
    end)

    lazy_teardown(function()
      if proxy_client then
        proxy_client:close()
      end

      if proxy_ssl_client_foo then
        proxy_ssl_client_foo:close()
      end

      if mtls_client then
        mtls_client:close()
      end

      if admin_client then
        admin_client:close()
      end

      helpers.stop_kong(nil, true)
    end)

    describe("filter cache is isolated per workspace", function()
      it("doesn't request cert for route that's in a different workspace", function()
        -- this maps to the default workspace
        local res = assert(proxy_ssl_client_foo:send {
          method  = "GET",
          path    = "/default",
          headers = {
            ["Host"] = "foo.com"
          }
        })
        assert.res_status(200, res)
      end)

      it("request cert for route applied the plugin", function()
        local res = assert(proxy_ssl_client_foo:send {
          method  = "GET",
          path    = "/anotherroute",
          headers = {
            ["Host"] = "foo.com"
          }
        })
        local body = assert.res_status(401, res)
        local json = cjson.decode(body)
        assert.same({ message = "No required TLS certificate was sent" }, json)
      end)

      it("still request cert for route applied the plugin", function()
        local res = assert(proxy_ssl_client_example:send {
          method  = "GET",
          path    = "/get",
          headers = {
            ["Host"] = "example.com"
          }
        })
        local body = assert.res_status(401, res)
        local json = cjson.decode(body)
        assert.same({ message = "No required TLS certificate was sent" }, json)
      end)

      it("returns HTTP 200 on https request if certificate validation passed", function()
        local res = assert(mtls_client:send {
          method  = "GET",
          path    = "/example_client",
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("foo@example.com", json.headers["x-consumer-username"])
        assert.equal(consumer.id, json.headers["x-consumer-id"])
        assert.equal("consumer-id-1", json.headers["x-consumer-custom-id"])
      end)
    end)
  end)

  describe("Plugin: mtls-auth (access) [#" .. strategy .. "]", function()
    local mtls_client
    local bp, db
    local service, route, plugin
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

      service = bp.services:insert{
        protocol = "https",
        port     = helpers.mock_upstream_ssl_port,
        host     = helpers.mock_upstream_ssl_host,
      }

      route = bp.routes:insert {
        hosts   = { "example.com" },
        service = { id = service.id, },
      }

      ca_cert = assert(db.ca_certificates:insert({
        cert = intermediate_CA,
      }))

      plugin = assert(bp.plugins:insert {
        name = "mtls-auth",
        route = { id = route.id },
        config = {
          ca_certificates = { ca_cert.id, },
          skip_consumer_lookup = true,
          allow_partial_chain = true,
        },
      })

      assert(helpers.start_kong({
        database   = db_strategy,
        plugins = "bundled,mtls-auth",
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }, nil, nil, mtls_fixtures))

    end)

    lazy_teardown(function()
      helpers.stop_kong(nil, true)
    end)

    describe("valid partial chain", function()
      it("allow certificate verification with only an intermediate certificate", function()
        mtls_client = helpers.http_client("127.0.0.1", 10121)
        local res = assert(mtls_client:send {
          method  = "GET",
          path    = "/intermediate_example_client",
        })
        assert.res_status(200, res)
        mtls_client:close()
      end)

      it("turn allow_partial_chain from true to false, reject the request", function()
        local res = assert(helpers.admin_client():send({
          method  = "PATCH",
          path    = "/routes/" .. route.id .. "/plugins/" .. plugin.id,
          body    = {
            config = { allow_partial_chain = false, },
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        }))
        assert.res_status(200, res)

        mtls_client = helpers.http_client("127.0.0.1", 10121)
        assert.eventually(function()
          local res = assert(mtls_client:send {
            method  = "GET",
            path    = "/intermediate_example_client",
          })
          assert.res_status(401, res)
        end).with_timeout(3)
            .has_no_error("Invalid response code")
        mtls_client:close()
      end)

      it("turn allow_partial_chain from false to true, accept the request again", function()
        local res = assert(helpers.admin_client():send({
          method  = "PATCH",
          path    = "/routes/" .. route.id .. "/plugins/" .. plugin.id,
          body    = {
            config = { allow_partial_chain = true, },
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        }))
        assert.res_status(200, res)

        mtls_client = helpers.http_client("127.0.0.1", 10121)
        assert.eventually(function()
          local res = assert(mtls_client:send {
            method  = "GET",
            path    = "/intermediate_example_client",
          })
          assert.res_status(200, res)
        end).with_timeout(3)
            .has_no_error("Invalid response code")
        mtls_client:close()
      end)
    end)
  end)
end
