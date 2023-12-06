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
MIIFwzCCA6ugAwIBAgIUeouSZPKRZLA8V7MPX0u4NDFCTpIwDQYJKoZIhvcNAQEL
BQAwaTELMAkGA1UEBhMCVVMxCzAJBgNVBAgMAkNBMQswCQYDVQQHDAJTRjEbMBkG
A1UECgwST3RoZXIgS29uZyBUZXN0aW5nMSMwIQYDVQQDDBpPdGhlciBLb25nIFRl
c3RpbmcgUm9vdCBDQTAeFw0yMTAyMjUwMDA4NDZaFw0zMTAyMjMwMDA4NDZaMGkx
CzAJBgNVBAYTAlVTMQswCQYDVQQIDAJDQTELMAkGA1UEBwwCU0YxGzAZBgNVBAoM
Ek90aGVyIEtvbmcgVGVzdGluZzEjMCEGA1UEAwwaT3RoZXIgS29uZyBUZXN0aW5n
IFJvb3QgQ0EwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQChJkXlW6uk
hFgvqa3qH5jtpLgnDK6V6oKrIcPfJluZzZJXl97VXuDTBVuTqHqI44fv3Fs43k/p
WUsOVA7kF8B6aZm1CPtf7KfZRBgyf/skI6ZnqdOSsyZpuF24dDYeADuR2fu15j0j
coBVMywVJujsMjha9jdF8kn04FnyRM/G2fKwnIUVMYHXYLPgXbmhZxeUBfD4i9Ze
hmqIqO6b1M5UHpeZg0rLUa/NG+yEtifPYnTXZzEOEZVJNiUqeqmLCqm5lDllLw9b
Sx80CgqhaaOtMs7RSO4S6nqvwyMfHG1zxO6OqghnsoZKc6+qejEPa6WM1fSkZZLe
kPQb4UE8jwkbxjIZms5/XW50oDQn8IhNvpXBbSXX7QYR53ZUdTeccfjRhO2Olo7e
P6tlxJRtB2d4BvjkDzVABaOz5ZHEJgM1XhAVoWfM4Np9i7vaZCTvDJ2ISKEH50/h
pSCXDmhseXTIP9eHkz65yBIx+mx4F83/NR9SSRMPoO3kjZlKLIdZzwG6zOq7qkvg
zOgkuf6Qleb3ZHJ+UTPMMbv9Gwk0xsK7hrPT+uaHmZiawy5R1I+7j+jJT3EYRm37
h+RXTHKz2Av1hK8dMT+lwbDmP2U9S8KOQuBUh3A2HIo3vcvdJoF5+cZTmvVX7wc2
uf9C/ltRcwUgtCBoZfydUgwq5V1m3HZAEwIDAQABo2MwYTAdBgNVHQ4EFgQUME+t
fYowqcbxGEb52whMGuf2FQcwHwYDVR0jBBgwFoAUME+tfYowqcbxGEb52whMGuf2
FQcwDwYDVR0TAQH/BAUwAwEB/zAOBgNVHQ8BAf8EBAMCAYYwDQYJKoZIhvcNAQEL
BQADggIBAJxdRYESsIFRTfvtMqeHvWP71SkEIBYhrzHWc4EZz3wZWfzOTUZ7mlqc
mGRLmkMfDk/DzObG87iG8WLzR8UWsVPpKSGLeKJ7Kd0WVqh0jrWlbI1boVwilXZg
i5P1ZHB+lL+CBokwjgo/IYeUKu+UQvoJ/Lf0OauhoBsw1rB7vwbWijf1wKZf6SpD
e9U6jeJrAByrqrghU6pXW4c+RrL7GJQoFdf6iFXKYzzmcvOmevt0vbXF8i2hqqRm
/6CfSteU1F4Q11pWpRffyXsV8ewq8gTCqLwOLqRxTrkx9r5HepwD8w37cdXvIaxO
F6qSLpVMJ/1XiCf5jebm2DKUYhZxbXEoKxJXPKHTVDCi3CQTmTKknWT1YUM3h3++
ctjjaE0A3ghaQnXU7mwzbsDZZgeORiyr+2TYJrxw6hTB/1MKoHdMWWfaU9m6lNtY
W5PeyXZS27+T4TWaIQw3HV5KCyH0Ddbgk6yf6vFIKLQ1jrQw0lpaZMAukv8jA1xZ
VwcnGuwhM10dEKzz2qqrAI3sxhgq9fhjH4djft9jLKoHfe9Nif9vy35rWb+Qkl0K
SCkFZdUsnFUK89SxPodEGEQ2P1APPodud8NWHhq5g5Rzy1mHjaDpGN35VikrBJ7N
Y4veJn0kqP3GX+jkAHg/znb+gEQcLa410NvwCHHRXU/lTbPek2Lx
-----END CERTIFICATE-----
]]

local mtls_fixtures = { http_mock = {
  mtls_server_block = [[
    server {
        server_name mtls_test_client;
        listen 10121;

        location = /nosni {
            content_by_lua_block {
                local handle = io.popen("openssl s_client -connect 127.0.0.1:9443 > /tmp/output.txt", "w")
                if not handle then
                    ngx.log(ngx.ERR, "unable to popen openssl: ", err)
                    return ngx.exit(ngx.ERROR)
                end
                ngx.sleep(2)
                assert(handle:write("bad request\n"))
                handle:close()

                handle = io.popen("grep '^Acceptable client certificate CA names$\\|^C = US,\\|^No client certificate CA names sent$' /tmp/output.txt")
                if not handle then
                    ngx.log(ngx.ERR, "unable to popen grep: ", err)
                    return ngx.exit(ngx.ERROR)
                end
                ngx.print(handle:read("*a"))
                handle:close()
            }
        }

        location / {
            content_by_lua_block {
                local handle = io.popen("openssl s_client -connect 127.0.0.1:9443 -servername " .. ngx.var.uri:sub(2) .. ".test > /tmp/output.txt", "w")
                if not handle then
                    ngx.log(ngx.ERR, "unable to popen openssl: ", err)
                    return ngx.exit(ngx.ERROR)
                end
                ngx.sleep(2)
                assert(handle:write("bad request\n"))
                handle:close()

                handle = io.popen("grep '^Acceptable client certificate CA names$\\|^C = US,\\|^No client certificate CA names sent$' /tmp/output.txt")
                if not handle then
                    ngx.log(ngx.ERR, "unable to popen grep: ", err)
                    return ngx.exit(ngx.ERROR)
                end
                ngx.print(handle:read("*a"))
                handle:close()
            }
        }
    }
  ]], }
}

for _, strategy in strategies() do
  describe("Plugin: mtls-auth (send_ca_dn feature) [#" .. strategy .. "]", function()
    local proxy_client, admin_client, proxy_ssl_client, mtls_client
    local bp, db
    local service1, service2
    local route1, route2, route3, route4, route5, route6, route7, route8
    local plugin, plugin1, plugin5, plugin8
    local ca_cert, other_ca_cert, sub_ca_cert
    local db_strategy = strategy ~= "off" and strategy or nil

    lazy_setup(function()
      bp, db = helpers.get_db_utils(db_strategy, {
        "routes",
        "services",
        "plugins",
        "ca_certificates",
      }, { "mtls-auth", })

      service1 = bp.services:insert{
        protocol = "http",
        port     = 80,
        host     = "httpbin.org",
      }

      service2 = bp.services:insert{
        protocol = "http",
        port     = 80,
        host     = "httpbin.org",
      }

      -- routes to service1
      route1 = bp.routes:insert {
        snis   = { "test1.test" },
        service = { id = service1.id, },
      }

      route2 = bp.routes:insert {
        snis   = { "test2.test", "test2-alias.test" },
        service = { id = service1.id, },
      }

      route3 = bp.routes:insert {
        snis   = { "test3.test" },
        service = { id = service1.id, },
      }

      route4 = bp.routes:insert {
        snis   = { "test3.test" },
        service = { id = service1.id, },
      }

      route5 = bp.routes:insert {
        snis   = { "test4.test" },
        service = { id = service1.id, },
      }

      route6 = bp.routes:insert {
        snis   = { "test5.test" },
        service = { id = service1.id, },
      }

      route7 = bp.routes:insert {
        paths = {"/route7", },
        service = { id = service1.id, },
      }

      route8 = bp.routes:insert {
        snis   = { "test7.test" },
        service = { id = service1.id, },
      }

      -- routes to service2
      bp.routes:insert {    -- route9
        snis   = { "test4.test" },
        service = { id = service2.id, },
      }

      bp.routes:insert {    -- route10
        snis   = { "test6.test" },
        service = { id = service2.id, },
      }

      bp.routes:insert {    -- route11
        paths = {"/route11", },
        service = { id = service2.id, },
      }

      ca_cert = assert(db.ca_certificates:insert({
        cert = CA,
      }))

      sub_ca_cert = assert(db.ca_certificates:insert({
        cert = sub_CA,
      }))

      other_ca_cert = assert(db.ca_certificates:insert({
        cert = other_CA,
      }))

      -- global plugin
      plugin = assert(bp.plugins:insert {
        name = "mtls-auth",
        config = { ca_certificates = { other_ca_cert.id, }, send_ca_dn = true,},
      })

      -- plugin on routes(service1)
      plugin1 = assert(bp.plugins:insert {
        name = "mtls-auth",
        route = { id = route1.id },
        config = { ca_certificates = { ca_cert.id, }, send_ca_dn = true,},
      })

      assert(bp.plugins:insert {              -- plugin2
        name = "mtls-auth",
        route = { id = route2.id },
        config = { ca_certificates = { ca_cert.id, }, send_ca_dn = true,},
      })

      assert(bp.plugins:insert {              -- plugin3
        name = "mtls-auth",
        route = { id = route3.id },
        config = { ca_certificates = { ca_cert.id, }, send_ca_dn = true,},
      })

      assert(bp.plugins:insert {              -- plugin4
        name = "mtls-auth",
        route = { id = route4.id },
        config = { ca_certificates = { sub_ca_cert.id, }, send_ca_dn = true,},
      })

      plugin5 = assert(bp.plugins:insert {
        name = "mtls-auth",
        route = { id = route5.id },
        config = { ca_certificates = { ca_cert.id, }, send_ca_dn = true,},
      })

      assert(bp.plugins:insert {              -- plugin6
        name = "mtls-auth",
        route = { id = route6.id },
        config = { ca_certificates = { ca_cert.id, }, }, -- default send_ca_dn = false
      })

      assert(bp.plugins:insert {              -- plugin7
        name = "mtls-auth",
        route = { id = route7.id },
        config = { ca_certificates = { ca_cert.id, }, send_ca_dn = true,},
      })

      -- plugin on service2
      plugin8 = assert(bp.plugins:insert {
        name = "mtls-auth",
        service = { id = service2.id },
        config = { ca_certificates = { sub_ca_cert.id, }, send_ca_dn = true,},
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

    describe("initial config", function()
       it("default send_ca_dn=false, send no ca dn", function()
        local res = assert(mtls_client:send {
          method  = "GET",
          path    = "/test5",
          headers = {
            ["Host"] = "mtls_test_client"
          }
        })
        local body = assert.res_status(200, res)
        assert.truthy(string.find(body, "No client certificate CA names sent", 1, true))
      end)

      it("when client hello contains no sni, send the merged ca dn related to snis[\"*\"]", function()
        local res = assert(mtls_client:send {
          method  = "GET",
          path    = "/nosni",
          headers = {
            ["Host"] = "mtls_test_client"
          }
        })
        local body = assert.res_status(200, res)
        assert.truthy(string.find(body, "Acceptable client certificate CA names", 1, true))
        assert.truthy(string.find(body, "C = US, ST = California, O = Kong Testing, CN = Kong Testing Intermidiate CA", 1, true))
        assert.truthy(string.find(body, "C = US, ST = California, O = Kong Testing, CN = Kong Testing Root CA", 1, true))
        assert.truthy(string.find(body, "C = US, ST = CA, L = SF, O = Other Kong Testing, CN = Other Kong Testing Root CA", 1, true))
      end)

      it("when client hello contains unknown sni, send the merged ca dn related to snis[\"*\"]", function()
        local res = assert(mtls_client:send {
          method  = "GET",
          path    = "/unknown",
          headers = {
            ["Host"] = "mtls_test_client"
          }
        })
        local body = assert.res_status(200, res)
        assert.truthy(string.find(body, "Acceptable client certificate CA names", 1, true))
        assert.truthy(string.find(body, "C = US, ST = California, O = Kong Testing, CN = Kong Testing Intermidiate CA", 1, true))
        assert.truthy(string.find(body, "C = US, ST = California, O = Kong Testing, CN = Kong Testing Root CA", 1, true))
        assert.truthy(string.find(body, "C = US, ST = CA, L = SF, O = Other Kong Testing, CN = Other Kong Testing Root CA", 1, true))
      end)

      it("mtls plugin applied on a route with sni, send the related ca dn when client hello contains the sni", function()
        local res = assert(mtls_client:send {
          method  = "GET",
          path    = "/test1",
          headers = {
            ["Host"] = "mtls_test_client"
          }
        })
        local body = assert.res_status(200, res)
        assert.truthy(string.find(body, "Acceptable client certificate CA names", 1, true))
        assert.falsy(string.find(body, "C = US, ST = California, O = Kong Testing, CN = Kong Testing Intermidiate CA", 1, true))
        assert.truthy(string.find(body, "C = US, ST = California, O = Kong Testing, CN = Kong Testing Root CA", 1, true))
        assert.falsy(string.find(body, "C = US, ST = CA, L = SF, O = Other Kong Testing, CN = Other Kong Testing Root CA", 1, true))
      end)

      it("mtls plugin applied on a service whose route contains sni, send the related ca dn when client hello contains the sni", function()
        local res = assert(mtls_client:send {
          method  = "GET",
          path    = "/test6",
          headers = {
            ["Host"] = "mtls_test_client"
          }
        })
        local body = assert.res_status(200, res)
        assert.truthy(string.find(body, "Acceptable client certificate CA names", 1, true))
        assert.truthy(string.find(body, "C = US, ST = California, O = Kong Testing, CN = Kong Testing Intermidiate CA", 1, true))
        assert.falsy(string.find(body, "C = US, ST = California, O = Kong Testing, CN = Kong Testing Root CA", 1, true))
        assert.falsy(string.find(body, "C = US, ST = CA, L = SF, O = Other Kong Testing, CN = Other Kong Testing Root CA", 1, true))
      end)

      it("mtls plugin applied on a route with multiple snis, send the related ca dn when client hello contains one of the snis #1", function()
        local res = assert(mtls_client:send {
          method  = "GET",
          path    = "/test2",
          headers = {
            ["Host"] = "mtls_test_client"
          }
        })
        local body = assert.res_status(200, res)
        assert.truthy(string.find(body, "Acceptable client certificate CA names", 1, true))
        assert.falsy(string.find(body, "C = US, ST = California, O = Kong Testing, CN = Kong Testing Intermidiate CA", 1, true))
        assert.truthy(string.find(body, "C = US, ST = California, O = Kong Testing, CN = Kong Testing Root CA", 1, true))
        assert.falsy(string.find(body, "C = US, ST = CA, L = SF, O = Other Kong Testing, CN = Other Kong Testing Root CA", 1, true))
      end)

      it("mtls plugin applied on a route with multiple snis, send the related ca dn when client hello contains one of the snis #2", function()
        local res = assert(mtls_client:send {
          method  = "GET",
          path    = "/test2-alias",
          headers = {
            ["Host"] = "mtls_test_client"
          }
        })
        local body = assert.res_status(200, res)
        assert.truthy(string.find(body, "Acceptable client certificate CA names", 1, true))
        assert.falsy(string.find(body, "C = US, ST = California, O = Kong Testing, CN = Kong Testing Intermidiate CA", 1, true))
        assert.truthy(string.find(body, "C = US, ST = California, O = Kong Testing, CN = Kong Testing Root CA", 1, true))
        assert.falsy(string.find(body, "C = US, ST = CA, L = SF, O = Other Kong Testing, CN = Other Kong Testing Root CA", 1, true))
      end)

      it("multiple mtls plugin applied on multiple routes with the same sni, send the merged ca dn when client hello contains the sni", function()
        local res = assert(mtls_client:send {
          method  = "GET",
          path    = "/test3",
          headers = {
            ["Host"] = "mtls_test_client"
          }
        })
        local body = assert.res_status(200, res)
        assert.truthy(string.find(body, "Acceptable client certificate CA names", 1, true))
        assert.truthy(string.find(body, "C = US, ST = California, O = Kong Testing, CN = Kong Testing Intermidiate CA", 1, true))
        assert.truthy(string.find(body, "C = US, ST = California, O = Kong Testing, CN = Kong Testing Root CA", 1, true))
        assert.falsy(string.find(body, "C = US, ST = CA, L = SF, O = Other Kong Testing, CN = Other Kong Testing Root CA", 1, true))
      end)

      it("multiple mtls plugin applied on a route and a service with the same sni, send the merged ca dn when client hello contains the sni", function()
        local res = assert(mtls_client:send {
          method  = "GET",
          path    = "/test4",
          headers = {
            ["Host"] = "mtls_test_client"
          }
        })
        local body = assert.res_status(200, res)
        assert.truthy(string.find(body, "Acceptable client certificate CA names", 1, true))
        assert.truthy(string.find(body, "C = US, ST = California, O = Kong Testing, CN = Kong Testing Intermidiate CA", 1, true))
        assert.truthy(string.find(body, "C = US, ST = California, O = Kong Testing, CN = Kong Testing Root CA", 1, true))
        assert.falsy(string.find(body, "C = US, ST = CA, L = SF, O = Other Kong Testing, CN = Other Kong Testing Root CA", 1, true))
      end)
    end)

    if strategy ~= "off" then
      describe("update route: remove sni in the route", function()
        lazy_setup(function()
          local old_cache = wait_until_cache_invalidated(nil, 5)

          local res = assert(admin_client:send({
            method  = "PATCH",
            path    = "/routes/" .. route1.id,
            body    = {
            snis = {},
            paths = {"/route1",},
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
            path    = "/services/" .. service1.id .. "/routes/" .. route1.id,
            body    = {
              snis   = {"test1.test"},
	            paths  = {},
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          }))
          assert.res_status(200, res)
        end)

        it("removing test1.test, test1.test will be considered as unknown sni #aaa", function()
          local res = assert(mtls_client:send {
            method  = "GET",
            path    = "/test1",
            headers = {
              ["Host"] = "mtls_test_client"
            }
          })
          local body = assert.res_status(200, res)
          assert.truthy(string.find(body, "Acceptable client certificate CA names", 1, true))
          assert.truthy(string.find(body, "C = US, ST = California, O = Kong Testing, CN = Kong Testing Intermidiate CA", 1, true))
          assert.truthy(string.find(body, "C = US, ST = California, O = Kong Testing, CN = Kong Testing Root CA", 1, true))
          assert.truthy(string.find(body, "C = US, ST = CA, L = SF, O = Other Kong Testing, CN = Other Kong Testing Root CA", 1, true))
        end)
      end)

      describe("update route: add sni in the route", function()
        lazy_setup(function()
          local old_cache = wait_until_cache_invalidated(nil, 5)

          local res = assert(admin_client:send({
            method  = "PATCH",
            path    = "/routes/" .. route1.id,
            body    = {
              snis   = {"test1.test", "test7.test"},
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
              snis   = {"test1.test"},
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          }))
          assert.res_status(200, res)
        end)

        it("will send corresponding ca dn when sni is test7.test", function()
          local res = assert(mtls_client:send {
            method  = "GET",
            path    = "/test7",
            headers = {
              ["Host"] = "mtls_test_client"
            }
          })
          local body = assert.res_status(200, res)
          assert.truthy(string.find(body, "Acceptable client certificate CA names", 1, true))
          assert.falsy(string.find(body, "C = US, ST = California, O = Kong Testing, CN = Kong Testing Intermidiate CA", 1, true))
          assert.truthy(string.find(body, "C = US, ST = California, O = Kong Testing, CN = Kong Testing Root CA", 1, true))
          assert.falsy(string.find(body, "C = US, ST = CA, L = SF, O = Other Kong Testing, CN = Other Kong Testing Root CA", 1, true))
        end)

        it("will send corresponding ca dn when sni is test1.test", function()
          local res = assert(mtls_client:send {
            method  = "GET",
            path    = "/test1",
            headers = {
              ["Host"] = "mtls_test_client"
            }
          })
          local body = assert.res_status(200, res)
          assert.truthy(string.find(body, "Acceptable client certificate CA names", 1, true))
          assert.falsy(string.find(body, "C = US, ST = California, O = Kong Testing, CN = Kong Testing Intermidiate CA", 1, true))
          assert.truthy(string.find(body, "C = US, ST = California, O = Kong Testing, CN = Kong Testing Root CA", 1, true))
          assert.falsy(string.find(body, "C = US, ST = CA, L = SF, O = Other Kong Testing, CN = Other Kong Testing Root CA", 1, true))
        end)
      end)

      describe("update route: update sni in the route", function()
        lazy_setup(function()
          local old_cache = wait_until_cache_invalidated(nil, 5)

          local res = assert(admin_client:send({
            method  = "PATCH",
            path    = "/routes/" .. route1.id,
            body    = {
              snis   = {"test7.test"},
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
              snis   = {"test1.test"},
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          }))
          assert.res_status(200, res)
        end)

        it("will send corresponding ca dn to test7.test", function()
          local res = assert(mtls_client:send {
            method  = "GET",
            path    = "/test7",
            headers = {
              ["Host"] = "mtls_test_client"
            }
          })
          local body = assert.res_status(200, res)
          assert.truthy(string.find(body, "Acceptable client certificate CA names", 1, true))
          assert.falsy(string.find(body, "C = US, ST = California, O = Kong Testing, CN = Kong Testing Intermidiate CA", 1, true))
          assert.truthy(string.find(body, "C = US, ST = California, O = Kong Testing, CN = Kong Testing Root CA", 1, true))
          assert.falsy(string.find(body, "C = US, ST = CA, L = SF, O = Other Kong Testing, CN = Other Kong Testing Root CA", 1, true))
        end)

        it("will send corresponding ca dn to snis[\"*\"]", function()
          local res = assert(mtls_client:send {
            method  = "GET",
            path    = "/test1",
            headers = {
              ["Host"] = "mtls_test_client"
            }
          })
          local body = assert.res_status(200, res)
          assert.truthy(string.find(body, "Acceptable client certificate CA names", 1, true))
          assert.truthy(string.find(body, "C = US, ST = California, O = Kong Testing, CN = Kong Testing Intermidiate CA", 1, true))
          assert.truthy(string.find(body, "C = US, ST = California, O = Kong Testing, CN = Kong Testing Root CA", 1, true))
          assert.truthy(string.find(body, "C = US, ST = CA, L = SF, O = Other Kong Testing, CN = Other Kong Testing Root CA", 1, true))
        end)
      end)

      describe("update plugin on route: update ca_ertificates", function()
        lazy_setup(function()
          local old_cache = wait_until_cache_invalidated(nil, 5)

          local res = assert(admin_client:send({
            method  = "PATCH",
            path    = "/routes/" .. route1.id .. "/plugins/" .. plugin1.id,
            headers = {
              ["Content-Type"] = "application/json"
            },
            body    = {
              config = { ca_certificates = { sub_ca_cert.id, },},
            }
          }))
          assert.res_status(200, res)

          wait_until_cache_invalidated(old_cache, 5)
        end)
        lazy_teardown(function()
          local res = assert(admin_client:send({
            method  = "PATCH",
            path    = "/routes/" .. route1.id .. "/plugins/" .. plugin1.id,
            headers = {
              ["Content-Type"] = "application/json"
            },
            body    = {
              config = { ca_certificates = { ca_cert.id, },},
            }
          }))
          assert.res_status(200, res)
        end)

        it("will send corresponding ca dn updated", function()
          local res = assert(mtls_client:send {
            method  = "GET",
            path    = "/test1",
            headers = {
              ["Host"] = "mtls_test_client"
            }
          })
          local body = assert.res_status(200, res)
          assert.truthy(string.find(body, "Acceptable client certificate CA names", 1, true))
          assert.truthy(string.find(body, "C = US, ST = California, O = Kong Testing, CN = Kong Testing Intermidiate CA", 1, true))
          assert.falsy(string.find(body, "C = US, ST = California, O = Kong Testing, CN = Kong Testing Root CA", 1, true))
          assert.falsy(string.find(body, "C = US, ST = CA, L = SF, O = Other Kong Testing, CN = Other Kong Testing Root CA", 1, true))
        end)
      end)

      describe("update plugin on route: change send_ca_dn to false", function()
        lazy_setup(function()
          local old_cache = wait_until_cache_invalidated(nil, 5)

          local res = assert(admin_client:send({
            method  = "PATCH",
            path    = "/routes/" .. route1.id .. "/plugins/" .. plugin1.id,
            headers = {
              ["Content-Type"] = "application/json"
            },
            body    = {
              config = { send_ca_dn = false, },
            }
          }))
          assert.res_status(200, res)

          wait_until_cache_invalidated(old_cache, 5)
        end)
        lazy_teardown(function()
          local res = assert(admin_client:send({
            method  = "PATCH",
            path    = "/routes/" .. route1.id .. "/plugins/" .. plugin1.id,
            headers = {
              ["Content-Type"] = "application/json"
            },
            body    = {
              config = { send_ca_dn = true, },
            }
          }))
          assert.res_status(200, res)
        end)

        it("no ca dn will be sent", function()
          local res = assert(mtls_client:send {
            method  = "GET",
            path    = "/test1",
            headers = {
              ["Host"] = "mtls_test_client"
            }
          })
          local body = assert.res_status(200, res)
          assert.truthy(string.find(body, "No client certificate CA names sent", 1, true))
        end)
      end)

      describe("update plugin on route: disable the plugin", function()
        lazy_setup(function()
          local old_cache = wait_until_cache_invalidated(nil, 5)

          local res = assert(admin_client:send({
            method  = "PATCH",
            path    = "/routes/" .. route1.id .. "/plugins/" .. plugin1.id,
            headers = {
              ["Content-Type"] = "application/json"
            },
            body    = {
              enabled = false,
            }
          }))
          assert.res_status(200, res)

          wait_until_cache_invalidated(old_cache, 5)
        end)
        lazy_teardown(function()
          local res = assert(admin_client:send({
            method  = "PATCH",
            path    = "/routes/" .. route1.id .. "/plugins/" .. plugin1.id,
            headers = {
              ["Content-Type"] = "application/json"
            },
            body    = {
              enabled = true,
            }
          }))
          assert.res_status(200, res)
        end)

        it("test1.test will be considered as unknown", function()
          local res = assert(mtls_client:send {
            method  = "GET",
            path    = "/test1",
            headers = {
              ["Host"] = "mtls_test_client"
            }
          })
          local body = assert.res_status(200, res)
          assert.truthy(string.find(body, "Acceptable client certificate CA names", 1, true))
          assert.truthy(string.find(body, "C = US, ST = California, O = Kong Testing, CN = Kong Testing Intermidiate CA", 1, true))
          assert.truthy(string.find(body, "C = US, ST = California, O = Kong Testing, CN = Kong Testing Root CA", 1, true))
          assert.truthy(string.find(body, "C = US, ST = CA, L = SF, O = Other Kong Testing, CN = Other Kong Testing Root CA", 1, true))
        end)
      end)

      describe("update plugin on service: update ca_ertificates", function()
        lazy_setup(function()
          local old_cache = wait_until_cache_invalidated(nil, 5)

          local res = assert(admin_client:send({
            method  = "PATCH",
            path    = "/services/" .. service2.id .. "/plugins/" .. plugin8.id,
            headers = {
              ["Content-Type"] = "application/json"
            },
            body    = {
              config = { ca_certificates = { ca_cert.id, },},
            }
          }))
          assert.res_status(200, res)

          wait_until_cache_invalidated(old_cache, 5)
        end)
        lazy_teardown(function()
          local res = assert(admin_client:send({
            method  = "PATCH",
            path    = "/services/" .. service2.id .. "/plugins/" .. plugin8.id,
            headers = {
              ["Content-Type"] = "application/json"
            },
            body    = {
              config = { ca_certificates = { sub_ca_cert.id, },},
            }
          }))
          assert.res_status(200, res)
        end)

        it("will send corresponding ca dn updated #1", function()
          local res = assert(mtls_client:send {
            method  = "GET",
            path    = "/test6",
            headers = {
              ["Host"] = "mtls_test_client"
            }
          })
          local body = assert.res_status(200, res)
          assert.truthy(string.find(body, "Acceptable client certificate CA names", 1, true))
          assert.falsy(string.find(body, "C = US, ST = California, O = Kong Testing, CN = Kong Testing Intermidiate CA", 1, true))
          assert.truthy(string.find(body, "C = US, ST = California, O = Kong Testing, CN = Kong Testing Root CA", 1, true))
          assert.falsy(string.find(body, "C = US, ST = CA, L = SF, O = Other Kong Testing, CN = Other Kong Testing Root CA", 1, true))
        end)

        it("will send corresponding ca dn updated #2", function()
          local res = assert(mtls_client:send {
            method  = "GET",
            path    = "/test4",
            headers = {
              ["Host"] = "mtls_test_client"
            }
          })
          local body = assert.res_status(200, res)
          assert.truthy(string.find(body, "Acceptable client certificate CA names", 1, true))
          assert.falsy(string.find(body, "C = US, ST = California, O = Kong Testing, CN = Kong Testing Intermidiate CA", 1, true))
          assert.truthy(string.find(body, "C = US, ST = California, O = Kong Testing, CN = Kong Testing Root CA", 1, true))
          assert.falsy(string.find(body, "C = US, ST = CA, L = SF, O = Other Kong Testing, CN = Other Kong Testing Root CA", 1, true))
        end)

        it("will send corresponding ca dn updated #3", function()
          local res = assert(mtls_client:send {
            method  = "GET",
            path    = "/nosni",
            headers = {
              ["Host"] = "mtls_test_client"
            }
          })
          local body = assert.res_status(200, res)
          assert.truthy(string.find(body, "Acceptable client certificate CA names", 1, true))
          assert.falsy(string.find(body, "C = US, ST = California, O = Kong Testing, CN = Kong Testing Intermidiate CA", 1, true))
          assert.truthy(string.find(body, "C = US, ST = California, O = Kong Testing, CN = Kong Testing Root CA", 1, true))
          assert.truthy(string.find(body, "C = US, ST = CA, L = SF, O = Other Kong Testing, CN = Other Kong Testing Root CA", 1, true))
        end)
      end)

      describe("update plugin on service: change send_ca_dn to false", function()
        lazy_setup(function()
          local old_cache = wait_until_cache_invalidated(nil, 5)

          local res = assert(admin_client:send({
            method  = "PATCH",
            path    = "/services/" .. service2.id .. "/plugins/" .. plugin8.id,
            headers = {
              ["Content-Type"] = "application/json"
            },
            body    = {
              config = { send_ca_dn = false, },
            }
          }))
          assert.res_status(200, res)

          wait_until_cache_invalidated(old_cache, 5)
        end)
        lazy_teardown(function()
          local res = assert(admin_client:send({
            method  = "PATCH",
            path    = "/services/" .. service2.id .. "/plugins/" .. plugin8.id,
            headers = {
              ["Content-Type"] = "application/json"
            },
            body    = {
              config = {send_ca_dn = true, },
            }
          }))
          assert.res_status(200, res)
        end)

        it("no ca dn will be sent if no other plugins applied on the sni", function()
          local res = assert(mtls_client:send {
            method  = "GET",
            path    = "/test6",
            headers = {
              ["Host"] = "mtls_test_client"
            }
          })
          local body = assert.res_status(200, res)
          assert.truthy(string.find(body, "No client certificate CA names sent", 1, true))
        end)

        it("the ca dn of this plugin will not be merged", function()
          local res = assert(mtls_client:send {
            method  = "GET",
            path    = "/test4",
            headers = {
              ["Host"] = "mtls_test_client"
            }
          })
          local body = assert.res_status(200, res)
          assert.truthy(string.find(body, "Acceptable client certificate CA names", 1, true))
          assert.falsy(string.find(body, "C = US, ST = California, O = Kong Testing, CN = Kong Testing Intermidiate CA", 1, true))
          assert.truthy(string.find(body, "C = US, ST = California, O = Kong Testing, CN = Kong Testing Root CA", 1, true))
          assert.falsy(string.find(body, "C = US, ST = CA, L = SF, O = Other Kong Testing, CN = Other Kong Testing Root CA", 1, true))
        end)

        it("the ca dn of this plugin will not be merged #2", function()
          local res = assert(mtls_client:send {
            method  = "GET",
            path    = "/nosni",
            headers = {
              ["Host"] = "mtls_test_client"
            }
          })
          local body = assert.res_status(200, res)
          assert.truthy(string.find(body, "Acceptable client certificate CA names", 1, true))
          assert.falsy(string.find(body, "C = US, ST = California, O = Kong Testing, CN = Kong Testing Intermidiate CA", 1, true))
          assert.truthy(string.find(body, "C = US, ST = California, O = Kong Testing, CN = Kong Testing Root CA", 1, true))
          assert.truthy(string.find(body, "C = US, ST = CA, L = SF, O = Other Kong Testing, CN = Other Kong Testing Root CA", 1, true))
        end)
      end)

      describe("update plugin on service: disable the plugin", function()
        lazy_setup(function()
          local old_cache = wait_until_cache_invalidated(nil, 5)

          local res = assert(admin_client:send({
            method  = "PATCH",
            path    = "/services/" .. service2.id .. "/plugins/" .. plugin8.id,
            headers = {
              ["Content-Type"] = "application/json"
            },
            body    = {
              enabled = false,
            }
          }))
          assert.res_status(200, res)

          wait_until_cache_invalidated(old_cache, 5)
        end)
        lazy_teardown(function()
          local res = assert(admin_client:send({
            method  = "PATCH",
            path    = "/services/" .. service2.id .. "/plugins/" .. plugin8.id,
            headers = {
              ["Content-Type"] = "application/json"
            },
            body    = {
              enabled = true,
            }
          }))
          assert.res_status(200, res)
        end)

        it("test6.test will be considered as unknown", function()
          local res = assert(mtls_client:send {
            method  = "GET",
            path    = "/test6",
            headers = {
              ["Host"] = "mtls_test_client"
            }
          })
          local body = assert.res_status(200, res)
          assert.truthy(string.find(body, "Acceptable client certificate CA names", 1, true))
          assert.falsy(string.find(body, "C = US, ST = California, O = Kong Testing, CN = Kong Testing Intermidiate CA", 1, true))
          assert.truthy(string.find(body, "C = US, ST = California, O = Kong Testing, CN = Kong Testing Root CA", 1, true))
          assert.truthy(string.find(body, "C = US, ST = CA, L = SF, O = Other Kong Testing, CN = Other Kong Testing Root CA", 1, true))
        end)

        it("the ca dn of this plugin will not be merged", function()
          local res = assert(mtls_client:send {
            method  = "GET",
            path    = "/test4",
            headers = {
              ["Host"] = "mtls_test_client"
            }
          })
          local body = assert.res_status(200, res)
          assert.truthy(string.find(body, "Acceptable client certificate CA names", 1, true))
          assert.falsy(string.find(body, "C = US, ST = California, O = Kong Testing, CN = Kong Testing Intermidiate CA", 1, true))
          assert.truthy(string.find(body, "C = US, ST = California, O = Kong Testing, CN = Kong Testing Root CA", 1, true))
          assert.falsy(string.find(body, "C = US, ST = CA, L = SF, O = Other Kong Testing, CN = Other Kong Testing Root CA", 1, true))
        end)

        it("the ca dn of this plugin will not be merged #2", function()
          local res = assert(mtls_client:send {
            method  = "get",
            path    = "/nosni",
            headers = {
              ["host"] = "mtls_test_client"
            }
          })
          local body = assert.res_status(200, res)
          assert.truthy(string.find(body, "Acceptable client certificate CA names", 1, true))
          assert.falsy(string.find(body, "C = US, ST = California, O = Kong Testing, CN = Kong Testing Intermidiate CA", 1, true))
          assert.truthy(string.find(body, "C = US, ST = California, O = Kong Testing, CN = Kong Testing Root CA", 1, true))
          assert.truthy(string.find(body, "C = US, ST = CA, L = SF, O = Other Kong Testing, CN = Other Kong Testing Root CA", 1, true))
        end)
      end)

      describe("update plugin on global: update ca_ertificates", function()
        lazy_setup(function()
          local old_cache = wait_until_cache_invalidated(nil, 5)

          local res = assert(admin_client:send({
            method  = "PATCH",
            path    = "/plugins/" .. plugin.id,
            headers = {
              ["Content-Type"] = "application/json"
            },
            body    = {
              config = { ca_certificates = { ca_cert.id, },},
            }
          }))
          assert.res_status(200, res)

          wait_until_cache_invalidated(old_cache, 5)
        end)
        lazy_teardown(function()
          local res = assert(admin_client:send({
            method  = "PATCH",
            path    = "/plugins/" .. plugin.id,
            headers = {
              ["Content-Type"] = "application/json"
            },
            body    = {
              config = { ca_certificates = { other_ca_cert.id, },},
            }
          }))
          assert.res_status(200, res)
        end)

        it("will send corresponding ca dn updated", function()
          local res = assert(mtls_client:send {
            method  = "GET",
            path    = "/nosni",
            headers = {
              ["Host"] = "mtls_test_client"
            }
          })
          local body = assert.res_status(200, res)
          assert.truthy(string.find(body, "Acceptable client certificate CA names", 1, true))
          assert.truthy(string.find(body, "C = US, ST = California, O = Kong Testing, CN = Kong Testing Intermidiate CA", 1, true))
          assert.truthy(string.find(body, "C = US, ST = California, O = Kong Testing, CN = Kong Testing Root CA", 1, true))
          assert.falsy(string.find(body, "C = US, ST = CA, L = SF, O = Other Kong Testing, CN = Other Kong Testing Root CA", 1, true))
        end)
      end)

      describe("update plugin on global: change send_ca_dn to false", function()
        lazy_setup(function()
          local old_cache = wait_until_cache_invalidated(nil, 5)

          local res = assert(admin_client:send({
            method  = "PATCH",
            path    = "/plugins/" .. plugin.id,
            headers = {
              ["Content-Type"] = "application/json"
            },
            body    = {
              config = { send_ca_dn = false, },
            }
          }))
          assert.res_status(200, res)

          wait_until_cache_invalidated(old_cache, 5)
        end)

        it("the ca dn of this plugin will not be merged", function()
          local res = assert(mtls_client:send {
            method  = "get",
            path    = "/nosni",
            headers = {
              ["host"] = "mtls_test_client"
            }
          })
          local body = assert.res_status(200, res)
          assert.truthy(string.find(body, "Acceptable client certificate CA names", 1, true))
          assert.truthy(string.find(body, "C = US, ST = California, O = Kong Testing, CN = Kong Testing Intermidiate CA", 1, true))
          assert.truthy(string.find(body, "C = US, ST = California, O = Kong Testing, CN = Kong Testing Root CA", 1, true))
          assert.falsy(string.find(body, "C = US, ST = CA, L = SF, O = Other Kong Testing, CN = Other Kong Testing Root CA", 1, true))
        end)
      end)

      describe("update plugin on global: change send_ca_dn back to true", function()
        lazy_setup(function()
          local old_cache = wait_until_cache_invalidated(nil, 5)

          local res = assert(admin_client:send({
            method  = "PATCH",
            path    = "/plugins/" .. plugin.id,
            headers = {
              ["Content-Type"] = "application/json"
            },
            body    = {
              config = {send_ca_dn = true, },
            }
          }))
          assert.res_status(200, res)

          wait_until_cache_invalidated(old_cache, 5)
        end)

        it("the ca dn of this plugin will be merged", function()
          local res = assert(mtls_client:send {
            method  = "get",
            path    = "/nosni",
            headers = {
              ["host"] = "mtls_test_client"
            }
          })
          local body = assert.res_status(200, res)
          assert.truthy(string.find(body, "Acceptable client certificate CA names", 1, true))
          assert.truthy(string.find(body, "C = US, ST = California, O = Kong Testing, CN = Kong Testing Intermidiate CA", 1, true))
          assert.truthy(string.find(body, "C = US, ST = California, O = Kong Testing, CN = Kong Testing Root CA", 1, true))
          assert.truthy(string.find(body, "C = US, ST = CA, L = SF, O = Other Kong Testing, CN = Other Kong Testing Root CA", 1, true))
        end)
      end)

      describe("update plugin on global: diable the plugin", function()
        lazy_setup(function()
          local old_cache = wait_until_cache_invalidated(nil, 5)

          local res = assert(admin_client:send({
            method  = "PATCH",
            path    = "/plugins/" .. plugin.id,
            headers = {
              ["Content-Type"] = "application/json"
            },
            body    = {
              enabled = false,
            }
          }))
          assert.res_status(200, res)

          wait_until_cache_invalidated(old_cache, 5)
        end)
        lazy_teardown(function()
          local res = assert(admin_client:send({
            method  = "PATCH",
            path    = "/plugins/" .. plugin.id,
            headers = {
              ["Content-Type"] = "application/json"
            },
            body    = {
              enabled = true,
            }
          }))
          assert.res_status(200, res)
        end)

        it("the ca dn of this plugin will not be merged", function()
          local res = assert(mtls_client:send {
            method  = "get",
            path    = "/nosni",
            headers = {
              ["host"] = "mtls_test_client"
            }
          })
          local body = assert.res_status(200, res)
          assert.truthy(string.find(body, "Acceptable client certificate CA names", 1, true))
          assert.truthy(string.find(body, "C = US, ST = California, O = Kong Testing, CN = Kong Testing Intermidiate CA", 1, true))
          assert.truthy(string.find(body, "C = US, ST = California, O = Kong Testing, CN = Kong Testing Root CA", 1, true))
          assert.falsy(string.find(body, "C = US, ST = CA, L = SF, O = Other Kong Testing, CN = Other Kong Testing Root CA", 1, true))
        end)
      end)

      describe("add plugin", function()
        local plugin_id
        lazy_setup(function()
          local old_cache = wait_until_cache_invalidated(nil, 5)

          local res = assert(admin_client:send({
            method  = "POST",
            path    = "/routes/" .. route8.id .. "/plugins/",
            headers = {
              ["Content-Type"] = "application/json"
            },
            body    = {
              name = "mtls-auth",
              config = { ca_certificates = { ca_cert.id, }, send_ca_dn = true,},
            }
          }))
          local body = assert.res_status(201, res)
          local json = cjson.decode(body)
          plugin_id = json.id

          wait_until_cache_invalidated(old_cache, 5)
        end)
        lazy_teardown(function()
          local res = assert(admin_client:send({
            method  = "DELETE",
            path    = "/routes/" .. route8.id .. "/plugins/" .. plugin_id,
            headers = {
              ["Content-Type"] = "application/json"
            },
          }))
          assert.res_status(204, res)
        end)

        it("will send the ca dn corresponding to this new plugin", function()
          local res = assert(mtls_client:send {
            method  = "get",
            path    = "/test7",
            headers = {
              ["host"] = "mtls_test_client"
            }
          })
          local body = assert.res_status(200, res)
          assert.truthy(string.find(body, "Acceptable client certificate CA names", 1, true))
          assert.falsy(string.find(body, "C = US, ST = California, O = Kong Testing, CN = Kong Testing Intermidiate CA", 1, true))
          assert.truthy(string.find(body, "C = US, ST = California, O = Kong Testing, CN = Kong Testing Root CA", 1, true))
          assert.falsy(string.find(body, "C = US, ST = CA, L = SF, O = Other Kong Testing, CN = Other Kong Testing Root CA", 1, true))
        end)
      end)

      -- at last
      describe("delete plugin", function()
        lazy_setup(function()
          local old_cache = wait_until_cache_invalidated(nil, 5)

          local res = assert(admin_client:send({
            method  = "DELETE",
            path    = "/routes/" .. route5.id .. "/plugins/" .. plugin5.id,
            headers = {
              ["Content-Type"] = "application/json"
            },
          }))
          assert.res_status(204, res)

          wait_until_cache_invalidated(old_cache, 5)
        end)
        lazy_teardown(function()
          local res = assert(admin_client:send({
            method  = "POST",
            path    = "/routes/" .. route5.id .. "/plugins/",
            headers = {
              ["Content-Type"] = "application/json"
            },
            body    = {
              name = "mtls-auth",
              config = { ca_certificates = { ca_cert.id, }, send_ca_dn = true,},
            }
          }))
          local body = assert.res_status(201, res)
          plugin5 = cjson.decode(body)
        end)

        it("the ca dn of the deleted plugin will be removed", function()
          local res = assert(mtls_client:send {
            method  = "get",
            path    = "/test4",
            headers = {
              ["host"] = "mtls_test_client"
            }
          })
          local body = assert.res_status(200, res)
          assert.truthy(string.find(body, "Acceptable client certificate CA names", 1, true))
          assert.truthy(string.find(body, "C = US, ST = California, O = Kong Testing, CN = Kong Testing Intermidiate CA", 1, true))
          assert.falsy(string.find(body, "C = US, ST = California, O = Kong Testing, CN = Kong Testing Root CA", 1, true))
          assert.falsy(string.find(body, "C = US, ST = CA, L = SF, O = Other Kong Testing, CN = Other Kong Testing Root CA", 1, true))
        end)
      end)
    end
  end)
end
