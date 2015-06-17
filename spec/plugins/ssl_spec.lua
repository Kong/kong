local spec_helper = require "spec.spec_helpers"
local ssl_util = require "kong.plugins.ssl.ssl_util"
local url = require "socket.url"
local IO = require "kong.tools.io"
local http_client = require "kong.tools.http_client"
local cjson = require "cjson"

local STUB_GET_SSL_URL = spec_helper.STUB_GET_SSL_URL
local STUB_GET_URL = spec_helper.STUB_GET_URL
local API_URL = spec_helper.API_URL

describe("SSL Plugin", function()

  setup(function()
    spec_helper.prepare_db()
    spec_helper.insert_fixtures {
      api = {
        { name = "API TESTS 11 (ssl)", public_dns = "ssl1.com", target_url = "http://mockbin.com" },
        { name = "API TESTS 12 (ssl)", public_dns = "ssl2.com", target_url = "http://mockbin.com" },
        { name = "API TESTS 13 (ssl)", public_dns = "ssl3.com", target_url = "http://mockbin.com" }
      },
      plugin_configuration = {
            { name = "ssl", value = { cert = [[
-----BEGIN CERTIFICATE-----
MIICSTCCAbICCQDZ7lxm1iUKmDANBgkqhkiG9w0BAQsFADBpMQswCQYDVQQGEwJV
UzETMBEGA1UECAwKQ2FsaWZvcm5pYTEWMBQGA1UEBwwNU2FuIEZyYW5jaXNjbzEN
MAsGA1UECgwES29uZzELMAkGA1UECwwCSVQxETAPBgNVBAMMCHNzbDEuY29tMB4X
DTE1MDUxOTAwNTAzNloXDTE1MDYxODAwNTAzNlowaTELMAkGA1UEBhMCVVMxEzAR
BgNVBAgMCkNhbGlmb3JuaWExFjAUBgNVBAcMDVNhbiBGcmFuY2lzY28xDTALBgNV
BAoMBEtvbmcxCzAJBgNVBAsMAklUMREwDwYDVQQDDAhzc2wxLmNvbTCBnzANBgkq
hkiG9w0BAQEFAAOBjQAwgYkCgYEAxOixlvURWF+WfMbG4alhrd3JcavYOGxiBcOv
0qA2v2a89S5JyD43O2uC8TfE6JZc3UT5kjRKRqIA8QDTYn3XGoJwkvYd1w9oXm3R
sZXXbi05PD0oXABtIIbH+0NllXRucdeODlXLi80mCvhVIIDjHifqDRiukecZGapE
rvTsPjMCAwEAATANBgkqhkiG9w0BAQsFAAOBgQCVQdpCfTZLJk0XUu5RnenHpamp
5ZRsdKA+jwE0kwuSWXx/WbsU35GJx1QVrfnmk7qJpwwg/ZbL/KMTUpY21a4ZyITQ
WKHxfY3Klqh18Ll7oBDa9fhuhPE4G8tIum/xY3Z3mHBuXDmBxARD0bOPEJtJQw+H
LGenf2mYrZBfL47wZw==
-----END CERTIFICATE-----
]], key = [[
-----BEGIN RSA PRIVATE KEY-----
MIICXQIBAAKBgQDE6LGW9RFYX5Z8xsbhqWGt3clxq9g4bGIFw6/SoDa/Zrz1LknI
Pjc7a4LxN8TollzdRPmSNEpGogDxANNifdcagnCS9h3XD2hebdGxldduLTk8PShc
AG0ghsf7Q2WVdG5x144OVcuLzSYK+FUggOMeJ+oNGK6R5xkZqkSu9Ow+MwIDAQAB
AoGAcYkqPLx5j9ct0ixbKGqd475qFJzdQ0tbCa/XhT7T0nDOqyBRcqBNAHnxOlzJ
sMJiMUNAE8kKusdWe5/aQoQErkVuO9sh1U6sPr7mVD/JWmE08MRzhMwxUVP+HsXM
EZky0M6TWNyghtvyElUiHTIW8quVdjn8oXQIbR/07VXEVmECQQDj6dHJ4XxXIvE1
HQ+49EbbM9l7KFd7t2cpmng1+U4yqMGwNVk3MmEVKU8NiI/BVhznPvp0HH3QyLpV
ShPt9SltAkEA3SzAZ5/UhjycKXgLsgidwDVWOpYweWU7KDsfrr+cSJkmzw7y9WYr
vshdPYA2iSm83aY1vTzwSRV6udpZfBLiHwJBAJ1HfDie3JmdSWtn1LPEDymyDEEL
Q+PiWtTA/nfwxV/8ST16c0i+AXUC/sTOGrZG4MdMFLYP+1sbSksVRc+OwbkCQQCy
DFKfmOUnYyd7oq4XliQYFVfjNgCz2TB0RJROwuV29ANv8GLZ9nQE05tr5QkCBl2K
OUFNo/7zdp0jfIlI/pKVAkA04q30OSEBIHBj/MmapVVSRaQiYfSMLV176nA4xqhz
JkHk9MH9WKKGIchn0LvfUFHxTeBFERoREQo2A82B/WpO
-----END RSA PRIVATE KEY-----
]] }, __api = 1 },
        { name = "ssl", value = { cert = [[
-----BEGIN CERTIFICATE-----
MIICSTCCAbICCQDZ7lxm1iUKmDANBgkqhkiG9w0BAQsFADBpMQswCQYDVQQGEwJV
UzETMBEGA1UECAwKQ2FsaWZvcm5pYTEWMBQGA1UEBwwNU2FuIEZyYW5jaXNjbzEN
MAsGA1UECgwES29uZzELMAkGA1UECwwCSVQxETAPBgNVBAMMCHNzbDEuY29tMB4X
DTE1MDUxOTAwNTAzNloXDTE1MDYxODAwNTAzNlowaTELMAkGA1UEBhMCVVMxEzAR
BgNVBAgMCkNhbGlmb3JuaWExFjAUBgNVBAcMDVNhbiBGcmFuY2lzY28xDTALBgNV
BAoMBEtvbmcxCzAJBgNVBAsMAklUMREwDwYDVQQDDAhzc2wxLmNvbTCBnzANBgkq
hkiG9w0BAQEFAAOBjQAwgYkCgYEAxOixlvURWF+WfMbG4alhrd3JcavYOGxiBcOv
0qA2v2a89S5JyD43O2uC8TfE6JZc3UT5kjRKRqIA8QDTYn3XGoJwkvYd1w9oXm3R
sZXXbi05PD0oXABtIIbH+0NllXRucdeODlXLi80mCvhVIIDjHifqDRiukecZGapE
rvTsPjMCAwEAATANBgkqhkiG9w0BAQsFAAOBgQCVQdpCfTZLJk0XUu5RnenHpamp
5ZRsdKA+jwE0kwuSWXx/WbsU35GJx1QVrfnmk7qJpwwg/ZbL/KMTUpY21a4ZyITQ
WKHxfY3Klqh18Ll7oBDa9fhuhPE4G8tIum/xY3Z3mHBuXDmBxARD0bOPEJtJQw+H
LGenf2mYrZBfL47wZw==
-----END CERTIFICATE-----
]], key = [[
-----BEGIN RSA PRIVATE KEY-----
MIICXQIBAAKBgQDE6LGW9RFYX5Z8xsbhqWGt3clxq9g4bGIFw6/SoDa/Zrz1LknI
Pjc7a4LxN8TollzdRPmSNEpGogDxANNifdcagnCS9h3XD2hebdGxldduLTk8PShc
AG0ghsf7Q2WVdG5x144OVcuLzSYK+FUggOMeJ+oNGK6R5xkZqkSu9Ow+MwIDAQAB
AoGAcYkqPLx5j9ct0ixbKGqd475qFJzdQ0tbCa/XhT7T0nDOqyBRcqBNAHnxOlzJ
sMJiMUNAE8kKusdWe5/aQoQErkVuO9sh1U6sPr7mVD/JWmE08MRzhMwxUVP+HsXM
EZky0M6TWNyghtvyElUiHTIW8quVdjn8oXQIbR/07VXEVmECQQDj6dHJ4XxXIvE1
HQ+49EbbM9l7KFd7t2cpmng1+U4yqMGwNVk3MmEVKU8NiI/BVhznPvp0HH3QyLpV
ShPt9SltAkEA3SzAZ5/UhjycKXgLsgidwDVWOpYweWU7KDsfrr+cSJkmzw7y9WYr
vshdPYA2iSm83aY1vTzwSRV6udpZfBLiHwJBAJ1HfDie3JmdSWtn1LPEDymyDEEL
Q+PiWtTA/nfwxV/8ST16c0i+AXUC/sTOGrZG4MdMFLYP+1sbSksVRc+OwbkCQQCy
DFKfmOUnYyd7oq4XliQYFVfjNgCz2TB0RJROwuV29ANv8GLZ9nQE05tr5QkCBl2K
OUFNo/7zdp0jfIlI/pKVAkA04q30OSEBIHBj/MmapVVSRaQiYfSMLV176nA4xqhz
JkHk9MH9WKKGIchn0LvfUFHxTeBFERoREQo2A82B/WpO
-----END RSA PRIVATE KEY-----
]], only_https = true }, __api = 2 }
      }
    }

    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
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
      local res = IO.os_execute("(echo \"GET /\"; sleep 2) | openssl s_client -connect "..parsed_url.host..":"..tostring(parsed_url.port).." -servername test4.com")

      assert.truthy(res:match("US/ST=California/L=San Francisco/O=Kong/OU=IT/CN=localhost"))
    end)

    it("should work when requesting a specific API", function()
      local parsed_url = url.parse(STUB_GET_SSL_URL)
      local res = IO.os_execute("(echo \"GET /\"; sleep 2) | openssl s_client -connect "..parsed_url.host..":"..tostring(parsed_url.port).." -servername ssl1.com")

      assert.truthy(res:match("US/ST=California/L=San Francisco/O=Kong/OU=IT/CN=ssl1.com"))
    end)

  end)

  describe("only_https", function()

    it("should block request without https", function()
      local response, status, headers = http_client.get(STUB_GET_URL, nil, { host = "ssl2.com" })
      assert.are.equal(426, status)
      assert.are.same("close, Upgrade", headers.connection)
      assert.are.same("TLS/1.0, HTTP/1.1", headers.upgrade)
      assert.are.same("Please use HTTPS protocol", cjson.decode(response).message)
    end)

    it("should not block request with https", function()
      local _, status = http_client.get(STUB_GET_SSL_URL, nil, { host = "ssl2.com" })
      assert.are.equal(200, status)
    end)

  end)
  
  describe("should work with curl", function()
    local response, status = http_client.get(API_URL.."/apis/", {public_dns="ssl3.com"})
    local api_id = cjson.decode(response).data[1].id
    local current_path = IO.os_execute("pwd")
    local res = IO.os_execute("curl -s -o /dev/null -w \"%{http_code}\" "..API_URL.."/apis/"..api_id.."/plugins/ --form \"name=ssl\" --form \"value.cert=@"..current_path.."/ssl/kong-default.crt\" --form \"value.key=@"..current_path.."/ssl/kong-default.key\"")
    assert.are.equal("201", res)
  end)

end)
