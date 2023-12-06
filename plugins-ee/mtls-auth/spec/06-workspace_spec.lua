-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson   = require "cjson"
local pl_tablex = require "pl.tablex"

local SNI_CACHE_KEY = "mtls-auth:cert_enabled_snis"

local strategies = helpers.all_strategies ~= nil and helpers.all_strategies or helpers.each_strategy

local function wait_until_cache_invalidated(old_cache, timeout)
  local new_cache
  helpers.wait_until(function()
    local admin_client = helpers.admin_client()
    local res = assert(admin_client:send({
      method  = "GET",
      path    = "/cache/" .. SNI_CACHE_KEY,
    }))

    if res.status == 404 then
      new_cache = nil
    elseif res.status == 200 then
      new_cache = assert(res:read_body())
      new_cache = cjson.decode(new_cache)
    end

    admin_client:close()

    if res.status == 404 or not pl_tablex.deepcompare(new_cache, old_cache) then
      return true
    end
  end)

  return new_cache
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

local sub_CA = [[
-----BEGIN CERTIFICATE-----
MIIFmjCCA4KgAwIBAgICEAAwDQYJKoZIhvcNAQELBQAwWDELMAkGA1UEBhMCVVMx
EzARBgNVBAgMCkNhbGlmb3JuaWExFTATBgNVBAoMDEtvbmcgVGVzdGluZzEdMBsG
A1UEAwwUS29uZyBUZXN0aW5nIFJvb3QgQ0EwHhcNMTkwNTAyMTk0MDQ4WhcNMjkw
NDI5MTk0MDQ4WjBgMQswCQYDVQQGEwJVUzETMBEGA1UECAwKQ2FsaWZvcm5pYTEV
MBMGA1UECgwMS29uZyBUZXN0aW5nMSUwIwYDVQQDDBxLb25nIFRlc3RpbmcgSW50
ZXJtaWRpYXRlIENBMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA0dnj
oHlJmNM94vQnK2FIIQJm9OAVvyMtAAkBKL7Cxt8G062GHDhq6gjQ9enuNQE0l3Vv
mSAh7N9gNlma6YbRB9VeG54BCuRQwCxveOBiwQvC2qrTzYI34kF/AeflrDOdzuLb
zj5cLADKXGCbGDtrSPKUwdlkuLs3pRr/YAyIQr7zJtlLz+E0GBYp0GWnLs0FiLSP
qSBWllC9u8gt2MiKyNlXw+kZ8lofOehCJzfFr6qagVklPw+8IpU6OGmRLFQVwVhp
zdAJmAGmSo/AGNKGqDdjzC4N2l4uYGH6n2KmY2yxsLBGZgwtLDst3fK4a3Wa5Tj7
cUwCcGLGtfVTaIXZYbqQ0nGsaYUd/mhx3B3Jk1p3ILZ72nVYowhpj22ipPGal5hp
ABh1MX3s/B+2ybWyDTtSaspcyhsRQsS6axB3DwLOLRy5Xp/kqEdConCtGCsjgm+U
FzdupubXK+KIAmTKXDx8OM7Af/K7kLDfFTre40sEB6fwrWwH8yFojeqkA/Uqhn5S
CzB0o4F3ON0xajsw2dRCziiq7pSe6ALLXetKpBr+xnVbUswH6BANUoDvh9thVPPx
1trkv+OuoJalkruZaT+38+iV9xwdqxnR7PUawqSyvrEAxjqUo7dDPsEuOpx1DJjO
XwRJCUjd7Ux913Iks24BqpPhEQz/rZzJLBApRVsCAwEAAaNmMGQwHQYDVR0OBBYE
FAsOBA6X+G1iTyTwO8Zv0go7jRERMB8GA1UdIwQYMBaAFAdP8giF4QLaR0HEj9N8
apTFYnD3MBIGA1UdEwEB/wQIMAYBAf8CAQAwDgYDVR0PAQH/BAQDAgGGMA0GCSqG
SIb3DQEBCwUAA4ICAQAWzIvIVM32iurqM451Amz0HNDG9j84cORnnaRR5opFTr3P
EqI3QkgCyP6YOs9t0QSbA4ur9WUzd3c9Ktj3qRRgTE+98JBOPO0rv+Kjj48aANDV
5tcbI9TZ9ap6g0jYr4XNT+KOO7E8QYlpY/wtokudCUDJE9vrsp1on4Bal2gjvCdh
SU0C1lnj6q6kBdQSYHrcjiEIGJH21ayVoNaBVP/fxyCHz472w1xN220dxUI/GqB6
pjcuy9cHjJHJKJbrkdt2eDRAFP5cILXc3mzUoGUDHY2JA1gtOHV0p4ix9R9AfI9x
snBEFiD8oIpcQay8MJH/z3NLEPLoBW+JaAAs89P+jcppea5N9vbiAkrPi687BFTP
PWPdstyttw6KrvtPQR1+FsVFcGeTjo32/UrckJixdiOEZgHk+deXpp7JoRdcsgzD
+okrsG79/LgS4icLmzNEp0IV36QckEq0+ALKDu6BXvWTkb5DB/FUrovZKJgkYeWj
GKogyrPIXrYi725Ff306124kLbxiA+6iBbKUtCutQnvut78puC6iP+a2SrfsbUJ4
qpvBFOY29Mlww88oWNGTA8QeW84Y1EJbRkHavzSsMFB73sxidQW0cHNC5t9RCKAQ
uibeZgK1Yk7YQKXdvbZvXwrgTcAjCdbppw2L6e0Uy+OGgNjnIps8K460SdaIiA==
-----END CERTIFICATE-----
]]

local other_CA = [[
-----BEGIN CERTIFICATE-----
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
-----END CERTIFICATE-----
]]

local mtls_fixtures = { http_mock = {
  mtls_server_block = [[
    server {
        server_name mtls_test_client;
        listen 10121;

        location / {
            proxy_ssl_certificate ../spec/fixtures/client_example.com.crt;
            proxy_ssl_certificate_key ../spec/fixtures/client_example.com.key;
            proxy_ssl_session_reuse off;
            proxy_ssl_name $arg_sni;
            proxy_ssl_server_name on;
            proxy_pass https://localhost:9443;
        }
    }
  ]], }
}

for _, strategy in strategies() do
  describe("Plugin: mtls-auth (routes of different workspaces can update normally) [#" .. strategy .. "]", function()
    local admin_client, mtls_client
    local bp, db
    local service1, route1
    local ca_cert, other_ca_cert, sub_ca_cert
    local ws1, ws1_service1, ws1_route1
    local db_strategy = strategy ~= "off" and strategy or nil

    lazy_setup(function()
      bp, db = helpers.get_db_utils(db_strategy, {
        "routes",
        "services",
        "plugins",
        "ca_certificates",
        "workspaces",
      }, { "mtls-auth", })

      ca_cert = assert(db.ca_certificates:insert({
        cert = CA,
      }))

      sub_ca_cert = assert(db.ca_certificates:insert({
        cert = sub_CA,
      }))

      other_ca_cert = assert(db.ca_certificates:insert({
        cert = other_CA,
      }))

      -- default workspace
      service1 = assert(bp.services:insert())

      -- basic route
      assert(bp.routes:insert {
        paths  = { "/", },
        service = { id = service1.id, },
      })

      route1 = assert(bp.routes:insert {
        snis   = { "default.test" },
        service = { id = service1.id, },
      })

      assert(bp.plugins:insert {
        name = "mtls-auth",
        route = { id = route1.id },
        config = { ca_certificates = { ca_cert.id, sub_ca_cert.id, other_ca_cert.id, },
                   skip_consumer_lookup = true, },
      })
      -- end default workspace

      -- workspace: ws1
      ws1 = assert(bp.workspaces:insert {
        name = "ws1"
      })

      ws1_service1 = assert(bp.services:insert_ws(nil, ws1))

      ws1_route1 = assert(bp.routes:insert_ws ({
        snis   = { "ws1.test" },
        service = { id = ws1_service1.id, },
      }, ws1))

      assert(bp.plugins:insert_ws ({
        name = "mtls-auth",
        route = { id = ws1_route1.id },
        config = { ca_certificates = { ca_cert.id, sub_ca_cert.id, other_ca_cert.id, },
                   skip_consumer_lookup = true, },
      }, ws1))
      -- end workspace: ws1

      assert(helpers.start_kong({
        database   = db_strategy,
        plugins = "bundled,mtls-auth",
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }, nil, nil, mtls_fixtures))

      mtls_client = helpers.http_client("127.0.0.1", 10121)
      admin_client = helpers.admin_client()
    end)

    lazy_teardown(function()
      if mtls_client then
        mtls_client:close()
      end

      if admin_client then
        admin_client:close()
      end

      helpers.stop_kong()
    end)

    describe("initial config", function()
      it("using unknown sni will not send cert request", function()
        helpers.clean_logfile()
        local res = assert(mtls_client:send {
          method  = "GET",
          path    = "/?sni=unknown.test",
          headers = {
            ["Host"] = "mtls_test_client"
          }
        })
        assert.res_status(200, res)
        assert.logfile().has.no.line("[mtls-auth] enabled, will request certificate from client", true)
      end)

      it("using sni of default workspace will send cert request", function()
        helpers.clean_logfile()
        local res = assert(mtls_client:send {
          method  = "GET",
          path    = "/?sni=default.test",
          headers = {
            ["Host"] = "mtls_test_client"
          }
        })
        assert.res_status(200, res)
        assert.logfile().has.line("[mtls-auth] enabled, will request certificate from client", true)
      end)

      it("using sni of workspace ws1 will send cert request", function()
        helpers.clean_logfile()
        local res = assert(mtls_client:send {
          method  = "GET",
          path    = "/?sni=ws1.test",
          headers = {
            ["Host"] = "mtls_test_client"
          }
        })
        assert.res_status(200, res)
        assert.logfile().has.line("[mtls-auth] enabled, will request certificate from client", true)
      end)
    end)

    if strategy ~= "off" then
      describe("update sni in default workspace", function()
        lazy_setup(function()
          local old_cache = wait_until_cache_invalidated(nil, 5)

          local res = assert(admin_client:send({
            method  = "PATCH",
            path    = "/routes/" .. route1.id,
            body    = {
              snis   = {"default-new.test"},
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          }))
          assert.res_status(200, res)

          wait_until_cache_invalidated(old_cache, 5)
        end)
        lazy_teardown(function()
          local res = assert(admin_client:send({
            method  = "PATCH",
            path    = "/routes/" .. route1.id,
            body    = {
              snis   = {"default.test"},
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          }))
          assert.res_status(200, res)
        end)

        it("default.test will be considered as unknown sni, thus will not send cert request", function()
          helpers.clean_logfile()
          local res = assert(mtls_client:send {
            method  = "GET",
            path    = "/?sni=default.test",
            headers = {
              ["Host"] = "mtls_test_client"
            }
          })
          assert.res_status(200, res)
          assert.logfile().has.no.line("[mtls-auth] enabled, will request certificate from client", true)
        end)

        it("new sni default-new.test takes effect, thus will send cert request", function()
          helpers.clean_logfile()
          local res = assert(mtls_client:send {
            method  = "GET",
            path    = "/?sni=ws1.test",
            headers = {
              ["Host"] = "mtls_test_client"
            }
          })
          assert.res_status(200, res)
          assert.logfile().has.line("[mtls-auth] enabled, will request certificate from client", true)
        end)
      end)

      describe("update sni in workspace ws1", function()
        lazy_setup(function()
          local old_cache = wait_until_cache_invalidated(nil, 5)

          local res = assert(admin_client:send({
            method  = "PATCH",
            path    = "/ws1/routes/" .. ws1_route1.id,
            body    = {
              snis   = {"ws1-new.test"},
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          }))
          assert.res_status(200, res)

          wait_until_cache_invalidated(old_cache, 5)
        end)
        lazy_teardown(function()
          local res = assert(admin_client:send({
            method  = "PATCH",
            path    = "/ws1/routes/" .. ws1_route1.id,
            body    = {
              snis   = {"ws1.test"},
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          }))
          assert.res_status(200, res)
        end)

        it("ws1.test will be considered as unknown sni, thus will not send cert request #only", function()
          helpers.clean_logfile()
          local res = assert(mtls_client:send {
            method  = "GET",
            path    = "/?sni=ws1.test",
            headers = {
              ["Host"] = "mtls_test_client"
            }
          })
          assert.res_status(200, res)
          assert.logfile().has.no.line("[mtls-auth] enabled, will request certificate from client", true)
        end)

        it("new sni ws1-new.test takes effect, thus will send cert request", function()
          helpers.clean_logfile()
          local res = assert(mtls_client:send {
            method  = "GET",
            path    = "/?sni=ws1-new.test",
            headers = {
              ["Host"] = "mtls_test_client"
            }
          })
          assert.res_status(200, res)
          assert.logfile().has.line("[mtls-auth] enabled, will request certificate from client", true)
        end)
      end)

    end
  end)
end
