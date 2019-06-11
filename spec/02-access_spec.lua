local helpers = require "spec.helpers"
local cjson   = require "cjson"
local meta    = require "kong.meta"
local utils   = require "kong.tools.utils"


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


for _, strategy in helpers.each_strategy() do
  describe("Plugin: mtls-auth (access) [#" .. strategy .. "]", function()
    local proxy_client, admin_client
    local bp, db
    local anonymous_user, consumer, customized_consumer, service, route
    local plugin
    local ca_cert

    lazy_setup(function()
      bp, db = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
        "consumers",
        "certificates",
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
        port     = 443,
        host     = "httpbin.org",
      }

      route = bp.routes:insert {
        hosts   = { "example.com" },
        service = { id = service.id, },
      }

      ca_cert = assert(db.certificates:insert({
        cert = CA,
      }))

      plugin = assert(bp.plugins:insert {
        name = "mtls-auth",
        route = { id = route.id },
        config = { certificate_authorities = { ca_cert.id }, },
      })

      assert(helpers.start_kong({
        database   = strategy,
        plugins = "bundled,mtls-auth",
        nginx_conf = "spec-ee/03-plugins/20-mtls-auth/fixtures/custom_nginx.template",
      }))

      proxy_client = helpers.proxy_client()
      proxy_ssl_client = helpers.proxy_ssl_client()
      mtls_client = helpers.http_client("127.0.0.1", 10121)
      admin_client = helpers.admin_client()
    end)

    lazy_teardown(function()
      if proxy_client then
        proxy_client:close()
      end

      if proxys_ssl_client then
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
      it("returns HTTP 496 on non-https request", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            ["Host"] = "example.com"
          }
        })
        local body = assert.res_status(496, res)
        local json = cjson.decode(body)
        assert.same({ message = "No required TLS certificate was sent" }, json)
      end)

      it("returns HTTP 496 on https request if mutual TLS was not completed", function()
        local res = assert(proxy_ssl_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            ["Host"] = "example.com"
          }
        })
        local body = assert.res_status(496, res)
        local json = cjson.decode(body)
        assert.same({ message = "No required TLS certificate was sent" }, json)
      end)

      it("returns HTTP 495 on https request if certificate validation failed", function()
        local res = assert(mtls_client:send {
          method  = "GET",
          path    = "/bad_client",
        })
        local body = assert.res_status(495, res)
        local json = cjson.decode(body)
        assert.same({ message = "TLS certificate failed verification" }, json)
      end)
    end)

    describe("valid certificate", function()
      it("returns HTTP 495 on https request if certificate validation failed", function()
        local res = assert(mtls_client:send {
          method  = "GET",
          path    = "/example_client",
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("foo@example.com", json.headers["X-Consumer-Username"])
        assert.equal(consumer.id, json.headers["X-Consumer-Id"])
        assert.equal("consumer-id-2", json.headers["X-Consumer-Custom-Id"])
      end)
    end)

    describe("custom credential", function()
      lazy_setup(function()
        local res = assert(admin_client:send({
          method  = "POST",
          path    = "/consumers/" .. customized_consumer.id  .. "/mtls-auth",
          body    = {
            subject_name   = "foo@example.com"
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        }))
        assert.res_status(201, res)
      end)

      it("overrides auto-matching", function()
        local res = assert(mtls_client:send {
          method  = "GET",
          path    = "/example_client",
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("customized@example.com", json.headers["X-Consumer-Username"])
        assert.equal(customized_consumer.id, json.headers["X-Consumer-Id"])
        assert.equal("consumer-id-3", json.headers["X-Consumer-Custom-Id"])
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

      it("works with right credentials and anonymous", function()
        local res = assert(mtls_client:send {
          method  = "GET",
          path    = "/example_client",
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("customized@example.com", json.headers["X-Consumer-Username"])
        assert.equal(customized_consumer.id, json.headers["X-Consumer-Id"])
        assert.equal("consumer-id-3", json.headers["X-Consumer-Custom-Id"])
        assert.is_nil(json.headers["X-Anonymous-Consumer"])
      end)

      it("works with wrong credentials and anonymous", function()
        local res = assert(mtls_client:send {
          method  = "GET",
          path    = "/bad_client",
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("anonymous@example.com", json.headers["X-Consumer-Username"])
        assert.equal(anonymous_user.id, json.headers["X-Consumer-Id"])
        assert.equal("consumer-id-1", json.headers["X-Consumer-Custom-Id"])
        assert.equal("true", json.headers["X-Anonymous-Consumer"])
      end)

      it("works with https (no mTLS handshake)", function()
        local res = assert(proxy_ssl_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            ["Host"] = "example.com"
          }
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("anonymous@example.com", json.headers["X-Consumer-Username"])
        assert.equal(anonymous_user.id, json.headers["X-Consumer-Id"])
        assert.equal("consumer-id-1", json.headers["X-Consumer-Custom-Id"])
        assert.equal("true", json.headers["X-Anonymous-Consumer"])
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
        assert.equal("anonymous@example.com", json.headers["X-Consumer-Username"])
        assert.equal(anonymous_user.id, json.headers["X-Consumer-Id"])
        assert.equal("consumer-id-1", json.headers["X-Consumer-Custom-Id"])
        assert.equal("true", json.headers["X-Anonymous-Consumer"])
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

        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            ["Host"] = "example.com"
          }
        })
        assert.res_status(500, res)
      end)
    end)
  end)
end
