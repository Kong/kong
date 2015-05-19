local spec_helper = require "spec.spec_helpers"
local http_client = require "kong.tools.http_client"
local ssl_util = require "kong.plugins.ssl.ssl_util"
local cjson = require "cjson"
local url = require "socket.url"
local utils = require "kong.tools.utils"
local IO = require "kong.tools.io"

STUB_GET_SSL_URL = spec_helper.STUB_GET_SSL_URL

describe("SSL Plugin", function()

  setup(function()
    spec_helper.prepare_db()
    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
    spec_helper.reset_db()
  end)
  
  describe("SSL Util", function()

    it("should not convert an invalid cert to DER", function()
      assert.falsy(ssl_util.cert_to_der("asd"))
    end)

     it("should convert a valid cert to DER", function()
      assert.truthy(ssl_util.cert_to_der([[
-----BEGIN CERTIFICATE-----
MIICUTCCAboCCQDmzZoyut/faTANBgkqhkiG9w0BAQsFADBtMQswCQYDVQQGEwJV
UzETMBEGA1UECAwKQ2FsaWZvcm5pYTEWMBQGA1UEBwwNU2FuIEZyYW5jaXNjbzEQ
MA4GA1UECgwHTWFzaGFwZTELMAkGA1UECwwCSVQxEjAQBgNVBAMMCWxvY2FsaG9z
dDAeFw0xNTA1MTUwMDA4MzZaFw0xNjA1MTQwMDA4MzZaMG0xCzAJBgNVBAYTAlVT
MRMwEQYDVQQIDApDYWxpZm9ybmlhMRYwFAYDVQQHDA1TYW4gRnJhbmNpc2NvMRAw
DgYDVQQKDAdNYXNoYXBlMQswCQYDVQQLDAJJVDESMBAGA1UEAwwJbG9jYWxob3N0
MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDDG3WEFIeL8YWyEaJ0L3QESzR9
Epg9d2p/y1v0xQgrwkM6sRFX81oNGdXssOeXAHJM6BXmMSbhfC+i3AkRPloltnwl
yEylOBaGY0GlPehZ9x+UxDiNpnjDakWWqXoFn1vDAU8gLTmduGVIGsQxT32sF0Y9
pFnbNQ0lU6cRe3/n8wIDAQABMA0GCSqGSIb3DQEBCwUAA4GBAHpVwlC75/LTKepa
VKHXqpk5H1zYsj2byBhYOY5/+aYbNqfa2DaWE1zwv/J4E7wgKaeQHHgT2XBtYSRM
ZMG9SgECUHZ+A/OebWgSfZvXbsIZ+PLk46rlZQ0O73kkbAyMTGNRvfEPeDmw0TR2
DYk+jZoTdElBV6PQAxysILNeJK5n
-----END CERTIFICATE-----
]]))
    end)

    it("should not convert an invalid key to DER", function()
      assert.falsy(ssl_util.key_to_der("asd"))
    end)

    it("should convert a valid key to DER", function()
      assert.truthy(ssl_util.key_to_der([[
-----BEGIN RSA PRIVATE KEY-----
MIICXAIBAAKBgQDDG3WEFIeL8YWyEaJ0L3QESzR9Epg9d2p/y1v0xQgrwkM6sRFX
81oNGdXssOeXAHJM6BXmMSbhfC+i3AkRPloltnwlyEylOBaGY0GlPehZ9x+UxDiN
pnjDakWWqXoFn1vDAU8gLTmduGVIGsQxT32sF0Y9pFnbNQ0lU6cRe3/n8wIDAQAB
AoGAdQQhBShy60Hd16Cv+FMFmBWq02C1ohfe7ep/qlwJvIT0YV0Vc9RmK/lUznKD
U5NW+j0v9TGBijc7MsgZQBhPY8aQXmwPfgaLq3YXjNJUITGwH0KAZe9WBiLObVZb
MDoa349PrjSpAkDryyF2wCmRBphUePd9BVeV/CR/a78BvSECQQDrWT2fqHjpSfKl
rjt9n29fWbj2Sfjkjaa+MK1l4tgDAVrfNLjsf6aXTBbSUWaTfpHG9E6frTMuE5pT
BcJf3TJJAkEA1DpBjavo8zpzjgmQ5SESrNB3+BYZYH9JRI91eIZYQzIvRgVRP+yG
vc0Hdhr1xSwN8XiFcVm24s5TEM+uE+bIWwJAQ24BKvJhGi4WuIOQBfEdPst9JAuT
pSA0qv9VXwC8dTf5KkR3y0LTnzusujuaUR4NdFxg/nzoUgZJzAm1ZDQDCQJBAKmq
sUG70A60CjHhv+8Ok8mJGIBD2qHk4QRo1Hc4oFOISXbnRV+fjtEqmu52+0lYwQTt
X3GRUb7dSFdGUVsjw8UCQH1sEtryRFIeCJgLT2p+UPYMNr6f/QYzpiK/M61xe2yf
IN2a44ptbkUjN8U0WeTGMBP/XfK3SvV6wAKAE3cDB2c=
-----END RSA PRIVATE KEY-----
]]))
    end)

  end)

  describe("SSL Resolution", function()

    it("should return default CERTIFICATE when requesting other APIs", function()
      local parsed_url = url.parse(STUB_GET_SSL_URL)
      local res, code = IO.os_execute("(echo \"GET /\"; sleep 2) | openssl s_client -connect "..parsed_url.host..":"..tostring(parsed_url.port).." -servername test4.com")
      
      assert.truthy(res:match("US/ST=California/L=San Francisco/O=Kong/OU=IT/CN=localhost"))
    end)

    it("should work when requesting a specific API", function()
      local parsed_url = url.parse(STUB_GET_SSL_URL)
      local res, code = IO.os_execute("(echo \"GET /\"; sleep 2) | openssl s_client -connect "..parsed_url.host..":"..tostring(parsed_url.port).." -servername ssl1.com")
      
      assert.truthy(res:match("US/ST=California/L=San Francisco/O=Kong/OU=IT/CN=ssl1.com"))
    end)

  end)

end)
