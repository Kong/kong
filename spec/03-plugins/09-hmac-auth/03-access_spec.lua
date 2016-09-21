local cjson = require "cjson"
local crypto = require "crypto"
local helpers = require "spec.helpers"

local hmac_sha1_binary = function(secret, data)
  return crypto.hmac.digest("sha1", data, secret, true)
end

local SIGNATURE_NOT_VALID = "HMAC signature cannot be verified"

describe("Plugin: hmac-auth (access)", function()
  local client, consumer, credential
  setup(function()
    assert(helpers.start_kong())
    client = helpers.proxy_client()

    local api1 = assert(helpers.dao.apis:insert {
      request_host = "hmacauth.com",
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "hmac-auth",
      api_id = api1.id,
      config = {
        clock_skew = 3000
      }
    })

    consumer = assert(helpers.dao.consumers:insert {
        username = "bob",
        custom_id = "1234"
    })
    credential = assert(helpers.dao["hmacauth_credentials"]:insert {
        username = "bob",
        secret = "secret",
        consumer_id = consumer.id
    })

    local api2 = assert(helpers.dao.apis:insert {
      request_host = "hmacauth2.com",
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "hmac-auth",
      api_id = api2.id,
      config = {
        anonymous = true,
        clock_skew = 3000
      }
    })
  end)

  teardown(function()
    if client then client:close() end
    helpers.stop_kong()
  end)

  describe("HMAC Authentication", function()
    it("should not be authorized when the hmac credentials are missing", function()
      local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
      local res = assert(client:send {
        method = "POST",
        body = {},
        headers = {
          ["HOST"] = "hmacauth.com",
          date = date
        }
      })
      local body = assert.res_status(401, res)
      body = cjson.decode(body)
      assert.equal("Unauthorized", body.message)
    end)

    it("should not be authorized when the HMAC signature is wrong", function()
      local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
      local res = assert(client:send {
        method = "POST",
        body = {},
        headers = {
          ["HOST"] = "hmacauth.com",
          date = date,
          authorization = "asd"
        }
      })
      local body = assert.res_status(403, res)
      body = cjson.decode(body)
      assert.equal(SIGNATURE_NOT_VALID, body.message)
    end)

    it("should not be authorized when date header is missing", function()
      local res = assert(client:send {
        method = "POST",
        body = {},
        headers = {
          ["HOST"] = "hmacauth.com",
          authorization = "asd"
        }
      })
      local body = assert.res_status(403, res)
      body = cjson.decode(body)
      assert.equal([[HMAC signature cannot be verified, ]]
                  ..[[a valid date or x-date header is]]
                  ..[[ required for HMAC Authentication]], body.message)
    end)

    it("should not be authorized with signature is wrong in proxy-authorization", function()
      local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
      local res = assert(client:send {
        method = "POST",
        body = {},
        headers = {
          ["HOST"] = "hmacauth.com",
          date = date,
          ["proxy-authorization"] = "asd"
        }
      })
      local body = assert.res_status(403, res)
      body = cjson.decode(body)
      assert.equal(SIGNATURE_NOT_VALID, body.message)
    end)

    it("should not pass when passing only the digest", function()
      local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
      local res = assert(client:send {
        method = "POST",
        body = {},
        headers = {
          ["HOST"] = "hmacauth.com",
          date = date,
          ["proxy-authorization"] = "hmac :dXNlcm5hbWU6cGFzc3dvcmQ="
        }
      })
      local body = assert.res_status(403, res)
      body = cjson.decode(body)
      assert.equal(SIGNATURE_NOT_VALID, body.message)
    end)

    it("should not pass when passing wrong hmac parameters", function()
      local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
      local res = assert(client:send {
        method = "POST",
        body = {},
        headers = {
          ["HOST"] = "hmacauth.com",
          date = date,
          ["proxy-authorization"] = [[hmac username=,algorithm,]]
            ..[[headers,dXNlcm5hbWU6cGFzc3dvcmQ=]]
        }
      })
      local body = assert.res_status(403, res)
      body = cjson.decode(body)
      assert.equal(SIGNATURE_NOT_VALID, body.message)
    end)

    it("should not pass when passing wrong hmac parameters", function()
      local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
      local res = assert(client:send {
        method = "POST",
        body = {},
        headers = {
          ["HOST"] = "hmacauth.com",
          date = date,
          authorization = [[hmac username=,algorithm,]]
            ..[[headers,dXNlcm5hbWU6cGFzc3dvcmQ=]]
        }
      })
      local body = assert.res_status(403, res)
      body = cjson.decode(body)
      assert.equal(SIGNATURE_NOT_VALID, body.message)
    end)

    it("should not be authorized when passing only the username", function()
      local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
      local res = assert(client:send {
        method = "POST",
        body = {},
        headers = {
          ["HOST"] = "hmacauth.com",
          date = date,
          authorization = "hmac username"
        }
      })
      local body = assert.res_status(403, res)
      body = cjson.decode(body)
      assert.equal(SIGNATURE_NOT_VALID, body.message)
    end)

    it("should not be authorized when authorization header is missing", function()
      local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
      local res = assert(client:send {
        method = "POST",
        body = {},
        headers = {
          ["HOST"] = "hmacauth.com",
          date = date,
        }
      })
      local body = assert.res_status(401, res)
      body = cjson.decode(body)
      assert.equal("Unauthorized", body.message)
    end)

    it("should pass with GET", function()
      local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
      local encodedSignature   = ngx.encode_base64(hmac_sha1_binary("secret", "date: "..date))
      local hmacAuth = [["hmac username="bob",algorithm="hmac-sha1",]]
        ..[[headers="date",signature="]]..encodedSignature..[["]]
      local res = assert(client:send {
        method = "GET",
        path = "/requests",
        body = {},
        headers = {
          ["HOST"] = "hmacauth.com",
          date = date,
          authorization = hmacAuth
        }
      })
      local body = assert.res_status(200, res)
      body = cjson.decode(body)
      assert.equal(hmacAuth, body.headers["authorization"])
    end)

    it("should pass with GET and proxy-authorization", function()
      local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
      local encodedSignature   = ngx.encode_base64(hmac_sha1_binary("secret", "date: "..date))
      local hmacAuth = [["hmac username="bob",algorithm="hmac-sha1",]]
        ..[[headers="date",signature="]]..encodedSignature..[["]]
      local res = assert(client:send {
        method = "GET",
        path = "/requests",
        body = {},
        headers = {
          ["HOST"] = "hmacauth.com",
          date = date,
          ["proxy-authorization"] = hmacAuth
        }
      })
      assert.res_status(200, res)
    end)

    it("should pass with POST", function()
      local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
      local encodedSignature   = ngx.encode_base64(hmac_sha1_binary("secret", "date: "..date))
      local hmacAuth = [["hmac username="bob",algorithm="hmac-sha1",]]
        ..[[headers="date",signature="]]..encodedSignature..[["]]
      local res = assert(client:send {
        method = "POST",
        path = "/requests",
        body = {},
        headers = {
          ["HOST"] = "hmacauth.com",
          date = date,
          authorization = hmacAuth
        }
      })
      local body = assert.res_status(200, res)
      body = cjson.decode(body)
      assert.equal(hmacAuth, body.headers["authorization"])
    end)

    it("should pass with GET and valid authorization and wrong proxy-authorization", function()
      local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
      local encodedSignature   = ngx.encode_base64(hmac_sha1_binary("secret", "date: "..date))
      local hmacAuth = [["hmac username="bob",algorithm="hmac-sha1",]]
        ..[[headers="date",signature="]]..encodedSignature..[["]]
      local res = assert(client:send {
        method = "POST",
        path = "/requests",
        body = {},
        headers = {
          ["HOST"] = "hmacauth.com",
          date = date,
          ["proxy-authorization"] = "hmac username",
          authorization = hmacAuth
        }
      })
      local body = assert.res_status(200, res)
      body = cjson.decode(body)
      assert.equal(hmacAuth, body.headers["authorization"])
    end)

    it("should pass with GET and invalid authorization and valid proxy-authorization", function()
      local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
      local encodedSignature   = ngx.encode_base64(
        hmac_sha1_binary("secret", "date: "..date))
      local hmacAuth = [["hmac username="bob",algorithm="hmac-sha1",]]
        ..[[headers="date",signature="]]..encodedSignature..[["]]
      local res = assert(client:send {
        method = "POST",
        path = "/requests",
        body = {},
        headers = {
          ["HOST"] = "hmacauth.com",
          date = date,
          ["proxy-authorization"] = hmacAuth,
          authorization = "hello"
        }
      })
      assert.res_status(200, res)
    end)

    it("should pass with GET with content-md5 header", function()
      local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
      local encodedSignature = ngx.encode_base64(
        hmac_sha1_binary("secret", "date: "..date.."\n".."content-md5: md5"))
      local hmacAuth = [["hmac username="bob",algorithm="hmac-sha1",]]
        ..[[headers="date content-md5",signature="]]..encodedSignature..[["]]
      local res = assert(client:send {
        method = "GET",
        path = "/requests",
        body = {},
        headers = {
          ["HOST"] = "hmacauth.com",
          date = date,
          ["proxy-authorization"] = hmacAuth,
          authorization = "hello",
          ["content-md5"] = "md5"
        }
      })
      assert.res_status(200, res)
    end)

    it("should pass with GET with request-line", function()
      local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
      local encodedSignature = ngx.encode_base64(
        hmac_sha1_binary("secret", "date: "
          ..date.."\n".."content-md5: md5".."\nGET /requests HTTP/1.1"))
      local hmacAuth = [["hmac username="bob",  algorithm="hmac-sha1", ]]
        ..[[headers="date content-md5 request-line", signature="]]
        ..encodedSignature..[["]]
      local res = assert(client:send {
        method = "GET",
        path = "/requests",
        body = {},
        headers = {
          ["HOST"] = "hmacauth.com",
          date = date,
          ["proxy-authorization"] = hmacAuth,
          authorization = "hello",
          ["content-md5"] = "md5"
        }
      })
      assert.res_status(200, res)
    end)

    it("should not pass with GET with wrong username in signature", function()
      local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
      local encodedSignature = ngx.encode_base64(
        hmac_sha1_binary("secret", "date: "..date.."\n"
        .."content-md5: md5".."\nGET /requests HTTP/1.1"))
      local hmacAuth = [["hmac username="bobb",  algorithm="hmac-sha1", ]]
        ..[[headers="date content-md5 request-line", signature="]]
        ..encodedSignature..[["]]
          local res = assert(client:send {
        method = "GET",
        path = "/requests",
        body = {},
        headers = {
          ["HOST"] = "hmacauth.com",
          date = date,
          ["proxy-authorization"] = hmacAuth,
          authorization = "hello",
          ["content-md5"] = "md5"
        }
      })

      local body = assert.res_status(403, res)
      body = cjson.decode(body)
      assert.equal(SIGNATURE_NOT_VALID, body.message)
    end)

    it("should not pass with GET with username blank in signature", function()
      local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
      local encodedSignature = ngx.encode_base64(
        hmac_sha1_binary("secret",
          "date: "..date.."\n".."content-md5: md5".."\nGET /requests HTTP/1.1"))
      local hmacAuth = [["hmac username="",  algorithm="hmac-sha1",]]
        ..[[ headers="date content-md5 request-line", signature="]]
        ..encodedSignature..[["]]
      local res = assert(client:send {
        method = "GET",
        path = "/requests",
        body = {},
        headers = {
          ["HOST"] = "hmacauth.com",
          date = date,
          ["proxy-authorization"] = hmacAuth,
          authorization = "hello",
          ["content-md5"] = "md5"
        }
      })

      local body = assert.res_status(403, res)
      body = cjson.decode(body)
      assert.equal(SIGNATURE_NOT_VALID, body.message)
    end)

    it("should not pass with GET with username missing in signature", function()
      local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
      local encodedSignature = ngx.encode_base64(
        hmac_sha1_binary("secret",
          "date: "..date.."\n".."content-md5: md5"
          .."\nGET /requests HTTP/1.1"))
      local hmacAuth = [["hmac algorithm="hmac-sha1", ]]
        ..[[headers="date content-md5 request-line", signature="]]
        ..encodedSignature..[["]]
      local res = assert(client:send {
        method = "GET",
        path = "/requests",
        body = {},
        headers = {
          ["HOST"] = "hmacauth.com",
          date = date,
          ["proxy-authorization"] = hmacAuth,
          authorization = "hello",
          ["content-md5"] = "md5"
        }
      })

      local body = assert.res_status(403, res)
      body = cjson.decode(body)
      assert.equal(SIGNATURE_NOT_VALID, body.message)
    end)

    it("should not pass with GET with wrong hmac headers field name", function()
      local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
      local encodedSignature = ngx.encode_base64(
        hmac_sha1_binary("secret", "date: "..date.."\n"
          .."content-md5: md5".."\nGET /requests HTTP/1.1"))
      local hmacAuth = [["hmac username="bob",  algorithm="hmac-sha1",   ]]
        ..[[wrong_header="date content-md5 request-line", signature="]]
        ..encodedSignature..[["]]
      local res = assert(client:send {
        method = "GET",
        path = "/requests",
        body = {},
        headers = {
          ["HOST"] = "hmacauth.com",
          date = date,
          ["proxy-authorization"] = hmacAuth,
          authorization = "hello",
          ["content-md5"] = "md5"
        }
      })
      local body = assert.res_status(403, res)
      body = cjson.decode(body)
      assert.equal(SIGNATURE_NOT_VALID, body.message)
    end)

     it("should not pass with GET with wrong hmac signature field name", function()
      local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
      local encodedSignature = ngx.encode_base64(
        hmac_sha1_binary("secret", "date: "..date.."\n"
          .."content-md5: md5".."\nGET /requests HTTP/1.1"))
      local hmacAuth = [["hmac username="bob",  algorithm="hmac-sha1",]]
        ..[[   headers="date content-md5 request-line", wrong_signature="]]
        ..encodedSignature..[["]]
      local res = assert(client:send {
        method = "GET",
        path = "/requests",
        body = {},
        headers = {
          ["HOST"] = "hmacauth.com",
          date = date,
          ["proxy-authorization"] = hmacAuth,
          authorization = "hello",
          ["content-md5"] = "md5"
        }
      })
      local body = assert.res_status(403, res)
      body = cjson.decode(body)
      assert.equal(SIGNATURE_NOT_VALID, body.message)
    end)

    it("should not pass with GET with malformed hmac signature field", function()
      local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
      local encodedSignature = ngx.encode_base64(
        hmac_sha1_binary("secret", "date: "..date.."\n"
          .."content-md5: md5".."\nGET /requests HTTP/1.1"))
      local hmacAuth = [["hmac username="bob",  algorithm="hmac-sha1"]]
        ..[[ headers="date content-md5 request-line", signature="]]
        ..encodedSignature..[["]]
      local res = assert(client:send {
        method = "GET",
        path = "/requests",
        body = {},
        headers = {
          ["HOST"] = "hmacauth.com",
          date = date,
          ["proxy-authorization"] = hmacAuth,
          authorization = "hello",
          ["content-md5"] = "md5"
        }
      })
      local body = assert.res_status(403, res)
      body = cjson.decode(body)
      assert.equal(SIGNATURE_NOT_VALID, body.message)
    end)

    it("should not pass with GET with malformed hmac headers field", function()
      local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
      local encodedSignature = ngx.encode_base64(
        hmac_sha1_binary("secret", "date: "..date.."\n"
          .."content-md5: md5".."\nGET /request? HTTP/1.1"))
      local hmacAuth = [["hmac username="bob",  algorithm="hmac-sha1" ]]
        ..[[headers="  date content-md5 request-line",signature="]]
        ..encodedSignature..[["]]
      local res = assert(client:send {
        method = "GET",
        path = "/requests",
        body = {},
        headers = {
          ["HOST"] = "hmacauth.com",
          date = date,
          ["proxy-authorization"] = hmacAuth,
          authorization = "hello",
          ["content-md5"] = "md5"
        }
      })
      local body = assert.res_status(403, res)
      body = cjson.decode(body)
      assert.equal(SIGNATURE_NOT_VALID, body.message)
    end)

    it("should pass with GET with no space or space between hmac signatures fields", function()
      local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
      local encodedSignature = ngx.encode_base64(
      hmac_sha1_binary("secret", "date: "..date.."\n"
        .."content-md5: md5".."\nGET /requests HTTP/1.1"))
      local hmacAuth = [["hmac username="bob",algorithm="hmac-sha1",]]
        ..[[  headers="date content-md5 request-line",signature="]]
        ..encodedSignature..[["]]
      local res = assert(client:send {
        method = "GET",
        path = "/requests",
        body = {},
        headers = {
          ["HOST"] = "hmacauth.com",
          date = date,
          ["proxy-authorization"] = hmacAuth,
          authorization = "hello",
          ["content-md5"] = "md5"
        }
      })
      assert.res_status(200, res)
    end)

    it("should pass with GET with wrong algorithm", function()
      local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
      local encodedSignature = ngx.encode_base64(
        hmac_sha1_binary("secret", "date: "..date.."\n"
          .."content-md5: md5".."\nGET /requests HTTP/1.1"))
      local hmacAuth = [["hmac username="bob",algorithm="hmac-sha256",]]
        ..[[  headers="date content-md5 request-line",signature="]]
        ..encodedSignature..[["]]
      local res = assert(client:send {
        method = "GET",
        path = "/requests",
        body = {},
        headers = {
          ["HOST"] = "hmacauth.com",
          date = date,
          ["proxy-authorization"] = hmacAuth,
          authorization = "hello",
          ["content-md5"] = "md5"
        }
      })
      assert.res_status(200, res)
    end)

    it("should pass the right headers to the upstream server", function()
      local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
      local encodedSignature = ngx.encode_base64(
        hmac_sha1_binary("secret", "date: "..date.."\n"
          .."content-md5: md5".."\nGET /requests HTTP/1.1"))
      local hmacAuth = [["hmac username="bob",algorithm="hmac-sha256",]]
        ..[[  headers="date content-md5 request-line",signature="]]
        ..encodedSignature..[["]]
      local res = assert(client:send {
        method = "GET",
        path = "/requests",
        body = {},
        headers = {
          ["HOST"] = "hmacauth.com",
          date = date,
          ["proxy-authorization"] = hmacAuth,
          authorization = "hello",
          ["content-md5"] = "md5"
        }
      })
      local body = assert.res_status(200, res)
      local parsed_body = cjson.decode(body)
      assert.equal(consumer.id, parsed_body.headers["x-consumer-id"])
      assert.equal(consumer.username, parsed_body.headers["x-consumer-username"])
      assert.equal(credential.username, parsed_body.headers["x-credential-username"])
      assert.is_nil(parsed_body.headers["x-anonymous-consumer"])
    end)

    it("should pass with GET with x-date header", function()
      local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
      local encodedSignature = ngx.encode_base64(
        hmac_sha1_binary("secret", "x-date: "..date.."\n"
          .."content-md5: md5".."\nGET /requests HTTP/1.1"))
      local hmacAuth = [["hmac username="bob",algorithm="hmac-sha1",]]
        ..[[  headers="x-date content-md5 request-line",signature="]]
        ..encodedSignature..[["]]
      local res = assert(client:send {
        method = "GET",
        path = "/requests",
        body = {},
        headers = {
          ["HOST"] = "hmacauth.com",
          ["x-date"] = date,
          authorization = hmacAuth,
          ["content-md5"] = "md5"
        }
      })
      assert.res_status(200, res)
    end)

    it("should not pass with GET with both date and x-date missing", function()
      local encodedSignature = ngx.encode_base64(
        hmac_sha1_binary("secret", "content-md5: md5"
          .."\nGET /request? HTTP/1.1"))
      local hmacAuth = [["hmac username="bob",  algorithm="hmac-sha1",]]
        ..[[ headers="content-md5 request-line",signature="]]
        ..encodedSignature..[["]]
      local res = assert(client:send {
        method = "GET",
        path = "/requests",
        body = {},
        headers = {
          ["HOST"] = "hmacauth.com",
          ["proxy-authorization"] = hmacAuth,
          authorization = "hello",
          ["content-md5"] = "md5"
        }
      })
      local body = assert.res_status(403, res)
      body = cjson.decode(body)
      assert.equal([[HMAC signature cannot be verified, a valid date or]]
        ..[[ x-date header is required for HMAC Authentication]], body.message)
    end)

    it("should not pass with GET with x-date malformed", function()
      local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
      local encodedSignature = ngx.encode_base64(
        hmac_sha1_binary("secret", "x-date: "..date.."\n"
          .."content-md5: md5".."\nGET /request? HTTP/1.1"))
      local hmacAuth = [["hmac username="bob",algorithm="hmac-sha1",]]
        ..[[  headers="x-date content-md5 request-line",signature="]]
        ..encodedSignature..[["]]
      local res = assert(client:send {
        method = "GET",
        path = "/requests",
        body = {},
        headers = {
          ["HOST"] = "hmacauth.com",
          ["x-date"] = "wrong date",
          authorization = hmacAuth,
          ["content-md5"] = "md5"
        }
      })
      local body = assert.res_status(403, res)
      body = cjson.decode(body)
      assert.equal([[HMAC signature cannot be verified, a valid date or]]
        ..[[ x-date header is required for HMAC Authentication]], body.message)
    end)

    it("should pass with GET with x-date malformed but date correct", function()
      local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
      local encodedSignature = ngx.encode_base64(
        hmac_sha1_binary("secret", "content-md5: md5"
          .."\nGET /requests HTTP/1.1"))
      local hmacAuth = [["hmac username="bob",algorithm="hmac-sha1",]]
        ..[[  headers="content-md5 request-line",signature="]]
        ..encodedSignature..[["]]
      local res = assert(client:send {
        method = "GET",
        path = "/requests",
        body = {},
        headers = {
          ["HOST"] = "hmacauth.com",
          ["x-date"] = "wrong date",
          date = date,
          authorization = hmacAuth,
          ["content-md5"] = "md5"
        }
      })
      assert.res_status(200, res)
    end)

    it("should pass with x-date malformed but date correct and used for signature", function()
      local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
      local encodedSignature = ngx.encode_base64(
        hmac_sha1_binary("secret", "date: "..date.."\n"
          .."content-md5: md5".."\nGET /requests HTTP/1.1"))
      local hmacAuth = [["hmac username="bob",algorithm="hmac-sha1",]]
        ..[[  headers="date content-md5 request-line",signature="]]
        ..encodedSignature..[["]]
      local res = assert(client:send {
        method = "GET",
        path = "/requests",
        body = {},
        headers = {
          ["HOST"] = "hmacauth.com",
          ["x-date"] = "wrong date",
          date = date,
          authorization = hmacAuth,
          ["content-md5"] = "md5"
        }
      })
      assert.res_status(200, res)
    end)

    it("should with x-date malformed and used for signature but skew test pass", function()
      local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
      local encodedSignature = ngx.encode_base64(
        hmac_sha1_binary("secret", "x-date: ".."wrong date".."\n"
          .."content-md5: md5".."\nGET /requests HTTP/1.1"))
      local hmacAuth = [["hmac username="bob",algorithm="hmac-sha1",]]
        ..[[  headers="x-date content-md5 request-line",signature="]]
        ..encodedSignature..[["]]
            local res = assert(client:send {
        method = "GET",
        path = "/requests",
        body = {},
        headers = {
          ["HOST"] = "hmacauth.com",
          ["x-date"] = "wrong date",
          date = date,
          authorization = hmacAuth,
          ["content-md5"] = "md5"
        }
      })
      assert.res_status(200, res)
    end)

    it("should pass with date malformed and used for signature but skew test pass", function()
      local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
      local encodedSignature = ngx.encode_base64(
        hmac_sha1_binary("secret", "date: ".."wrong date".."\n"
          .."content-md5: md5".."\nGET /requests HTTP/1.1"))
      local hmacAuth = [["hmac username="bob",algorithm="hmac-sha1",]]
        ..[[  headers="date content-md5 request-line",signature="]]
        ..encodedSignature..[["]]
      local res = assert(client:send {
        method = "GET",
        path = "/requests",
        body = {},
        headers = {
          ["HOST"] = "hmacauth.com",
          ["x-date"] = date,
          date = "wrong date",
          authorization = hmacAuth,
          ["content-md5"] = "md5"
        }
      })
      assert.res_status(200, res)
    end)

    it("should pass with valid credentials and anonymous", function()
      local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
      local encodedSignature   = ngx.encode_base64(hmac_sha1_binary("secret", "date: "..date))
      local hmacAuth = [["hmac username="bob",algorithm="hmac-sha1",]]
        ..[[headers="date",signature="]]..encodedSignature..[["]]
      local res = assert(client:send {
        method = "GET",
        path = "/request",
        body = {},
        headers = {
          ["HOST"] = "hmacauth2.com",
          date = date,
          authorization = hmacAuth
        }
      })
      local body = assert.res_status(200, res)
      body = cjson.decode(body)
      assert.equal(hmacAuth, body.headers["authorization"])
      assert.equal("bob", body.headers["x-consumer-username"])
      assert.is_nil(body.headers["x-anonymous-consumer"])
    end)

    it("should pass with invalid credentials and anonymous", function()
      local res = assert(client:send {
        method = "GET",
        path = "/request",
        body = {},
        headers = {
          ["HOST"] = "hmacauth2.com"
        }
      })
      local body = assert.res_status(200, res)
      body = cjson.decode(body)
      assert.equal("true", body.headers["x-anonymous-consumer"])
      assert.is_nil(body.headers["x-consumer-username"])
    end)
  end)
end)
