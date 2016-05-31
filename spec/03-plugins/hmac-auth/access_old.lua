local spec_helper = require "spec.spec_helpers"
local http_client = require "kong.tools.http_client"
local cjson = require "cjson"
local crypto = require "crypto"
local base64 = require "base64"

local PROXY_URL = spec_helper.PROXY_URL
local STUB_GET_URL = spec_helper.STUB_GET_URL
local STUB_POST_URL = spec_helper.STUB_POST_URL
local hmac_sha1_binary = function(secret, data)
  return crypto.hmac.digest("sha1", data, secret, true)
end

local SIGNATURE_NOT_VALID = "HMAC signature cannot be verified"

describe("Authentication Plugin", function()

  setup(function()
    spec_helper.prepare_db()
    spec_helper.insert_fixtures {
      api = {
        {name = "tests-hmac-auth", request_host = "hmacauth.com", upstream_url = "http://mockbin.org/"},
        {name = "tests-hmac-auth2", request_host = "hmacauth2.com", upstream_url = "http://httpbin.org/"}
      },
      consumer = {
        {username = "hmacauth_tests_consuser"}
      },
      plugin = {
        {name = "hmac-auth", config = {clock_skew = 3000}, __api = 1},
        {name = "hmac-auth", config = {clock_skew = 3000}, __api = 2}
      },
      hmacauth_credential = {
        {username = "bob", secret = "secret", __consumer = 1}
      }
    }

    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
  end)

  describe("HMAC Authentication", function()

    it("should not be authorized when the hmac credentials are missing", function()
      local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
      local response, status = http_client.get(STUB_GET_URL, {}, {host = "hmacauth.com", date = date})
      local parsed_response = cjson.decode(response)
      assert.equal(401, status)
      assert.equal("Unauthorized", parsed_response.message)
    end)

    it("should not be authorized when the HMAC signature is wrong", function()
      local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
      local response, status = http_client.get(STUB_GET_URL, {}, {host = "hmacauth.com", date = date, authorization = "asd"})
      local body = cjson.decode(response)
      assert.equal(403, status)
      assert.equal(SIGNATURE_NOT_VALID, body.message)
    end)

    it("should not be authorized when date header is missing", function()
      local response, status = http_client.get(STUB_GET_URL, {}, {host = "hmacauth.com", ["proxy-authorization"] = "asd"})
      local body = cjson.decode(response)
      assert.equal(403, status)
      assert.equal("HMAC signature cannot be verified, a valid date or x-date header is required for HMAC Authentication", body.message)
    end)

    it("should not be authorized when the HMAC signature is wrong in proxy-authorization", function()
      local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
      local response, status = http_client.get(STUB_GET_URL, {}, {host = "hmacauth.com", date = date, ["proxy-authorization"] = "asd"})
      local body = cjson.decode(response)
      assert.equal(403, status)
      assert.equal(SIGNATURE_NOT_VALID, body.message)
    end)

    it("should not pass when passing only the digest", function()
      local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
      local response, status = http_client.get(STUB_GET_URL, {}, {host = "hmacauth.com",  date = date, authorization = "hmac :dXNlcm5hbWU6cGFzc3dvcmQ="})
      local body = cjson.decode(response)
      assert.equal(403, status)
      assert.equal(SIGNATURE_NOT_VALID, body.message)
    end)

    it("should not pass when passing wrong hmac parameters", function()
      local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
      local response, status = http_client.get(STUB_GET_URL, {}, {host = "hmacauth.com",  date = date, authorization = "hmac username=,algorithm,headers,dXNlcm5hbWU6cGFzc3dvcmQ="})
      local body = cjson.decode(response)
      assert.equal(403, status)
      assert.equal(SIGNATURE_NOT_VALID, body.message)
    end)
    
    it("should not pass when passing wrong hmac parameters", function()
      local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
      local response, status = http_client.get(STUB_GET_URL, {}, {host = "hmacauth.com",  date = date, authorization = "hmac username=,algorithm=,headers=,signature=dXNlcm5hbWU6cGFzc3dvcmQ="})
      local body = cjson.decode(response)
      assert.equal(403, status)
      assert.equal(SIGNATURE_NOT_VALID, body.message)
    end)

    it("should not be authorized when passing only the username", function()
      local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
      local response, status = http_client.get(STUB_GET_URL, {}, {host = "hmacauth.com",  date = date, authorization = "hmac username"})
      local body = cjson.decode(response)
      assert.equal(403, status)
      assert.equal(SIGNATURE_NOT_VALID, body.message)
    end)

    it("should not be authorized when authorization is missing", function()
      local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
      local response, status = http_client.get(STUB_GET_URL, {}, {host = "hmacauth.com",  date = date, authorization123 = "hmac username:dXNlcm5hbWU6cGFzc3dvcmQ="})
      local body = cjson.decode(response)
      assert.equal(401, status)
      assert.equal("Unauthorized", body.message)
    end)

    it("should pass with GET", function()
      local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
      local encodedSignature   = base64.encode(hmac_sha1_binary("secret", "date: "..date))
      local hmacAuth = [["hmac username="bob",algorithm="hmac-sha1",headers="date",signature="]]..encodedSignature..[["]]
      local response, status = http_client.get(STUB_GET_URL, {}, {host = "hmacauth.com",  date = date, authorization = hmacAuth})
      assert.equal(200, status)
      local parsed_response = cjson.decode(response)
      assert.equal(hmacAuth, parsed_response.headers["authorization"])
    end)

    it("should pass with GET and proxy-authorization", function()
      local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
      local encodedSignature   = base64.encode(hmac_sha1_binary("secret", "date: "..date))
      local hmacAuth = [["hmac username="bob",algorithm="hmac-sha1",headers="date",signature="]]..encodedSignature..[["]]
      local response, status = http_client.get(STUB_GET_URL, {}, {host = "hmacauth.com",  date = date, ["proxy-authorization"] = hmacAuth})
      assert.equal(200, status)
      local parsed_response = cjson.decode(response)
      assert.equal(nil, parsed_response.headers["authorization"])
    end)

    it("should pass with POST", function()
      local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
      local encodedSignature   = base64.encode(hmac_sha1_binary("secret", "date: "..date))
      local hmacAuth = [["hmac username="bob",algorithm="hmac-sha1",headers="date",signature="]]..encodedSignature..[["]]
      local response, status = http_client.post(STUB_POST_URL, {}, {host = "hmacauth.com",  date = date, authorization = hmacAuth})
      assert.equal(200, status)
      local parsed_response = cjson.decode(response)
      assert.equal(hmacAuth, parsed_response.headers["authorization"])
    end)

    it("should pass with GET and valid authorization and wrong proxy-authorization", function()
      local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
      local encodedSignature   = base64.encode(hmac_sha1_binary("secret", "date: "..date))
      local hmacAuth = [["hmac username="bob",algorithm="hmac-sha1",headers="date",signature="]]..encodedSignature..[["]]
      local response, status = http_client.get(STUB_GET_URL, {}, {host = "hmacauth.com",  date = date, ["proxy-authorization"] = "hmac username", authorization = hmacAuth})
      assert.equal(200, status)
      local parsed_response = cjson.decode(response)
      assert.equal(hmacAuth, parsed_response.headers["authorization"])
    end)

    it("should pass with GET and invalid authorization and valid proxy-authorization", function()
      local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
      local encodedSignature   = base64.encode(hmac_sha1_binary("secret", "date: "..date))
      local hmacAuth = [["hmac username="bob",algorithm="hmac-sha1",headers="date",signature="]]..encodedSignature..[["]]
      local response, status = http_client.get(STUB_GET_URL, {}, {host = "hmacauth.com",  date = date, ["proxy-authorization"] = hmacAuth, authorization ="hello"})
      assert.equal(200, status)
      local parsed_response = cjson.decode(response)
      assert.equal("hello", parsed_response.headers["authorization"])
    end)

    it("should pass with GET with content-md5", function()
      local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
      local encodedSignature = base64.encode(hmac_sha1_binary("secret", "date: "..date.."\n".."content-md5: md5"))
      local hmacAuth = [["hmac username="bob",algorithm="hmac-sha1",headers="date content-md5",signature="]]..encodedSignature..[["]]
      local response, status = http_client.get(STUB_GET_URL, {}, {host = "hmacauth.com",  date = date, ["proxy-authorization"] = hmacAuth, authorization = "hello", ["content-md5"] = "md5"})
      assert.equal(200, status)
      local parsed_response = cjson.decode(response)
      assert.equal("hello", parsed_response.headers["authorization"])
    end)

    it("should pass with GET with request-line", function()
      local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
      local encodedSignature = base64.encode(hmac_sha1_binary("secret", "date: "..date.."\n".."content-md5: md5".."\nGET /request? HTTP/1.1"))
      local hmacAuth = [["hmac username="bob",  algorithm="hmac-sha1",   headers="date content-md5 request-line", signature="]]..encodedSignature..[["]]
      local response, status = http_client.get(STUB_GET_URL, {}, {host = "hmacauth.com",  date = date, ["proxy-authorization"] = hmacAuth, authorization = "hello", ["content-md5"] = "md5"})
      assert.equal(200, status)
      local parsed_response = cjson.decode(response)
      assert.equal("hello", parsed_response.headers["authorization"])
    end)
    
    it("should not pass with GET with wrong username", function()
      local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
      local encodedSignature = base64.encode(hmac_sha1_binary("secret", "date: "..date.."\n".."content-md5: md5".."\nGET /request? HTTP/1.1"))
      local hmacAuth = [["hmac username="bobb",  algorithm="hmac-sha1",   headers="date content-md5 request-line", signature="]]..encodedSignature..[["]]
      local response, status = http_client.get(STUB_GET_URL, {}, {host = "hmacauth.com",  date = date, ["proxy-authorization"] = hmacAuth, authorization = "hello", ["content-md5"] = "md5"})
      local body = cjson.decode(response)
      assert.equal(403, status)
      assert.equal(SIGNATURE_NOT_VALID, body.message)
    end)
    
    it("should not pass with GET with username blank", function()
      local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
      local encodedSignature = base64.encode(hmac_sha1_binary("secret", "date: "..date.."\n".."content-md5: md5".."\nGET /request? HTTP/1.1"))
      local hmacAuth = [["hmac username="",  algorithm="hmac-sha1",   headers="date content-md5 request-line", signature="]]..encodedSignature..[["]]
      local response, status = http_client.get(STUB_GET_URL, {}, {host = "hmacauth.com",  date = date, ["proxy-authorization"] = hmacAuth, authorization = "hello", ["content-md5"] = "md5"})
      local body = cjson.decode(response)
      assert.equal(403, status)
      assert.equal(SIGNATURE_NOT_VALID, body.message)
    end)
    
    it("should not pass with GET with username missing", function()
      local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
      local encodedSignature = base64.encode(hmac_sha1_binary("secret", "date: "..date.."\n".."content-md5: md5".."\nGET /request? HTTP/1.1"))
      local hmacAuth = [["hmac algorithm="hmac-sha1",   headers="date content-md5 request-line", signature="]]..encodedSignature..[["]]
      local response, status = http_client.get(STUB_GET_URL, {}, {host = "hmacauth.com",  date = date, ["proxy-authorization"] = hmacAuth, authorization = "hello", ["content-md5"] = "md5"})
      local body = cjson.decode(response)
      assert.equal(403, status)
      assert.equal(SIGNATURE_NOT_VALID, body.message)
    end)
    
    it("should not pass with GET with wrong hmac headers field name", function()
      local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
      local encodedSignature = base64.encode(hmac_sha1_binary("secret", "date: "..date.."\n".."content-md5: md5".."\nGET /request? HTTP/1.1"))
      local hmacAuth = [["hmac username="bob",  algorithm="hmac-sha1",   header="date content-md5 request-line", signature="]]..encodedSignature..[["]]
      local response, status = http_client.get(STUB_GET_URL, {}, {host = "hmacauth.com",  date = date, ["proxy-authorization"] = hmacAuth, authorization = "hello", ["content-md5"] = "md5"})
      local body = cjson.decode(response)
      assert.equal(403, status)
      assert.equal(SIGNATURE_NOT_VALID, body.message)
    end)
    
     it("should not pass with GET with wrong hmac signature field name", function()
      local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
      local encodedSignature = base64.encode(hmac_sha1_binary("secret", "date: "..date.."\n".."content-md5: md5".."\nGET /request? HTTP/1.1"))
      local hmacAuth = [["hmac username="bob",  algorithm="hmac-sha1",   headers="date content-md5 request-line", signatures="]]..encodedSignature..[["]]
      local response, status = http_client.get(STUB_GET_URL, {}, {host = "hmacauth.com",  date = date, ["proxy-authorization"] = hmacAuth, authorization = "hello", ["content-md5"] = "md5"})
      local body = cjson.decode(response)
      assert.equal(403, status)
      assert.equal(SIGNATURE_NOT_VALID, body.message)
    end)
    
    it("should not pass with GET with malformed hmac signature field", function()
      local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
      local encodedSignature = base64.encode(hmac_sha1_binary("secret", "date: "..date.."\n".."content-md5: md5".."\nGET /request? HTTP/1.1"))
      local hmacAuth = [["hmac username="bob",  algorithm="hmac-sha1" headers="date content-md5 request-line",signature="]]..encodedSignature..[["]]
      local response, status = http_client.get(STUB_GET_URL, {}, {host = "hmacauth.com",  date = date, ["proxy-authorization"] = hmacAuth, authorization = "hello", ["content-md5"] = "md5"})
      local body = cjson.decode(response)
      assert.equal(403, status)
      assert.equal(SIGNATURE_NOT_VALID, body.message)
    end)
    
    it("should not pass with GET with malformed hmac headers field", function()
      local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
      local encodedSignature = base64.encode(hmac_sha1_binary("secret", "date: "..date.."\n".."content-md5: md5".."\nGET /request? HTTP/1.1"))
      local hmacAuth = [["hmac username="bob",  algorithm="hmac-sha1" headers="  date content-md5 request-line",signature="]]..encodedSignature..[["]]
      local response, status = http_client.get(STUB_GET_URL, {}, {host = "hmacauth.com",  date = date, ["proxy-authorization"] = hmacAuth, authorization = "hello", ["content-md5"] = "md5"})
      local body = cjson.decode(response)
      assert.equal(403, status)
      assert.equal(SIGNATURE_NOT_VALID, body.message)
    end)
    
    it("should pass with GET with no space or space between hmac signatures fields", function()
      local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
      local encodedSignature = base64.encode(hmac_sha1_binary("secret", "date: "..date.."\n".."content-md5: md5".."\nGET /request? HTTP/1.1"))
      local hmacAuth = [["hmac username="bob",algorithm="hmac-sha1",  headers="date content-md5 request-line",signature="]]..encodedSignature..[["]]
      local response, status = http_client.get(STUB_GET_URL, {}, {host = "hmacauth.com",  date = date, ["proxy-authorization"] = hmacAuth, authorization = "hello", ["content-md5"] = "md5"})
      assert.equal(200, status)
      local parsed_response = cjson.decode(response)
      assert.equal("hello", parsed_response.headers["authorization"])
    end)
    
    it("should pass with GET with wrong algorithm", function()
      local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
      local encodedSignature = base64.encode(hmac_sha1_binary("secret", "date: "..date.."\n".."content-md5: md5".."\nGET /request? HTTP/1.1"))
      local hmacAuth = [["hmac username="bob",algorithm="hmac-sha256",  headers="date content-md5 request-line",signature="]]..encodedSignature..[["]]
      local response, status = http_client.get(STUB_GET_URL, {}, {host = "hmacauth.com",  date = date, ["proxy-authorization"] = hmacAuth, authorization = "hello", ["content-md5"] = "md5"})
      assert.equal(200, status)
      local parsed_response = cjson.decode(response)
      assert.equal("hello", parsed_response.headers["authorization"])
    end)

    it("should pass the right headers to the upstream server", function()
      local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
      local encodedSignature = base64.encode(hmac_sha1_binary("secret", "date: "..date.."\n".."content-md5: md5".."\nGET /headers? HTTP/1.1"))
      local hmacAuth = [["hmac username="bob",algorithm="hmac-sha256",  headers="date content-md5 request-line",signature="]]..encodedSignature..[["]]
      local response, status = http_client.get(PROXY_URL.."/headers", {}, {host = "hmacauth2.com",  date = date, ["proxy-authorization"] = hmacAuth, authorization = "hello", ["content-md5"] = "md5"})
      assert.equal(200, status)
      local parsed_response = cjson.decode(response)
      assert.truthy(parsed_response.headers["X-Consumer-Id"])
      assert.truthy(parsed_response.headers["X-Consumer-Username"])
      assert.truthy(parsed_response.headers["X-Credential-Username"])
      assert.equal("bob", parsed_response.headers["X-Credential-Username"])
    end) 
    
    it("should pass with GET with x-date header", function()
      local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
      local encodedSignature = base64.encode(hmac_sha1_binary("secret", "x-date: "..date.."\n".."content-md5: md5".."\nGET /request? HTTP/1.1"))
      local hmacAuth = [["hmac username="bob",algorithm="hmac-sha1",  headers="x-date content-md5 request-line",signature="]]..encodedSignature..[["]]
      local response, status = http_client.get(STUB_GET_URL, {}, {host = "hmacauth.com",  ["x-date"] = date, authorization = hmacAuth, ["content-md5"] = "md5"})
      assert.equal(200, status)
      local parsed_response = cjson.decode(response)
      assert.equal(hmacAuth, parsed_response.headers["authorization"])
    end)
    
    it("should not pass with GET with both date and x-date missing", function()
      local encodedSignature = base64.encode(hmac_sha1_binary("secret", "content-md5: md5".."\nGET /request? HTTP/1.1"))
      local hmacAuth = [["hmac username="bob",  algorithm="hmac-sha1" headers="content-md5 request-line",signature="]]..encodedSignature..[["]]
      local response, status = http_client.get(STUB_GET_URL, {}, {host = "hmacauth.com", ["proxy-authorization"] = hmacAuth, authorization = "hello", ["content-md5"] = "md5"})
      local body = cjson.decode(response)
      assert.equal(403, status)
      assert.equal("HMAC signature cannot be verified, a valid date or x-date header is required for HMAC Authentication", body.message)
    end)
    
    it("should not pass with GET with x-date malformed", function()
      local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
      local encodedSignature = base64.encode(hmac_sha1_binary("secret", "x-date: "..date.."\n".."content-md5: md5".."\nGET /request? HTTP/1.1"))
      local hmacAuth = [["hmac username="bob",algorithm="hmac-sha1",  headers="x-date content-md5 request-line",signature="]]..encodedSignature..[["]]
      local response, status = http_client.get(STUB_GET_URL, {}, {host = "hmacauth.com",  ["x-date"] = "wrong date", authorization = hmacAuth, ["content-md5"] = "md5"})
      local body = cjson.decode(response)
      assert.equal(403, status)
      assert.equal("HMAC signature cannot be verified, a valid date or x-date header is required for HMAC Authentication", body.message)
    end)
    
    it("should pass with GET with x-date malformed but date correct", function()
      local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
      local encodedSignature = base64.encode(hmac_sha1_binary("secret", "content-md5: md5".."\nGET /request? HTTP/1.1"))
      local hmacAuth = [["hmac username="bob",algorithm="hmac-sha1",  headers="content-md5 request-line",signature="]]..encodedSignature..[["]]
      local response, status = http_client.get(STUB_GET_URL, {}, {host = "hmacauth.com",  ["x-date"] = "wrong date", date = date, authorization = hmacAuth, ["content-md5"] = "md5"})
      assert.equal(200, status)
      local parsed_response = cjson.decode(response)
      assert.equal(hmacAuth, parsed_response.headers["authorization"])
    end)
    
    it("should pass with GET with x-date malformed but date correct and used for signature", function()
      local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
      local encodedSignature = base64.encode(hmac_sha1_binary("secret", "date: "..date.."\n".."content-md5: md5".."\nGET /request? HTTP/1.1"))
      local hmacAuth = [["hmac username="bob",algorithm="hmac-sha1",  headers="date content-md5 request-line",signature="]]..encodedSignature..[["]]
      local response, status = http_client.get(STUB_GET_URL, {}, {host = "hmacauth.com",  ["x-date"] = "wrong date", date = date, authorization = hmacAuth, ["content-md5"] = "md5"})
      assert.equal(200, status)
      local parsed_response = cjson.decode(response)
      assert.equal(hmacAuth, parsed_response.headers["authorization"])
    end)
    
    it("should pass with GET with x-date malformed and used for signature but skew test pass", function()
      local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
      local encodedSignature = base64.encode(hmac_sha1_binary("secret", "x-date: ".."wrong date".."\n".."content-md5: md5".."\nGET /request? HTTP/1.1"))
      local hmacAuth = [["hmac username="bob",algorithm="hmac-sha1",  headers="x-date content-md5 request-line",signature="]]..encodedSignature..[["]]
      local response, status = http_client.get(STUB_GET_URL, {}, {host = "hmacauth.com",  ["x-date"] = "wrong date", date = date, authorization = hmacAuth, ["content-md5"] = "md5"})
      assert.equal(200, status)
      local parsed_response = cjson.decode(response)
      assert.equal(hmacAuth, parsed_response.headers["authorization"])
    end)
    
    it("should pass with GET with date malformed and used for signature but skew test pass", function()
      local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
      local encodedSignature = base64.encode(hmac_sha1_binary("secret", "date: ".."wrong date".."\n".."content-md5: md5".."\nGET /request? HTTP/1.1"))
      local hmacAuth = [["hmac username="bob",algorithm="hmac-sha1",  headers="date content-md5 request-line",signature="]]..encodedSignature..[["]]
      local response, status = http_client.get(STUB_GET_URL, {}, {host = "hmacauth.com",  ["x-date"] = date, date = "wrong date", authorization = hmacAuth, ["content-md5"] = "md5"})
      assert.equal(200, status)
      local parsed_response = cjson.decode(response)
      assert.equal(hmacAuth, parsed_response.headers["authorization"])
    end)

  end)
end)
