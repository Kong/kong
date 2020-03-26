local cjson = require "cjson"
local openssl_hmac = require "resty.openssl.hmac"
local helpers = require "spec.helpers"
local utils = require "kong.tools.utils"
local resty_sha256 = require "resty.sha256"

local fmt = string.format


local hmac_sha1_binary = function(secret, data)
  return openssl_hmac.new(secret, "sha1"):final(data)
end


local SIGNATURE_NOT_VALID = "HMAC signature cannot be verified"


for _, strategy in helpers.each_strategy() do
  describe("Plugin: hmac-auth (access) [#" .. strategy .. "]", function()
    local proxy_client
    local consumer
    local credential

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "consumers",
        "plugins",
        "hmacauth_credentials",
      })

      local route1 = bp.routes:insert {
        hosts = { "hmacauth.com" },
      }

      bp.plugins:insert {
        name     = "hmac-auth",
        route = { id = route1.id },
        config   = {
          clock_skew = 3000
        }
      }

      consumer = bp.consumers:insert {
        username  = "bob",
        custom_id = "1234"
      }

      credential = bp.hmacauth_credentials:insert {
        username = "bob",
        secret   = "secret",
        consumer = { id = consumer.id },
      }

      local anonymous_user = bp.consumers:insert {
        username = "no-body"
      }

      local route2 = bp.routes:insert {
        hosts = { "hmacauth2.com" },
      }

      bp.plugins:insert {
        name     = "hmac-auth",
        route = { id = route2.id },
        config   = {
          anonymous  = anonymous_user.id,
          clock_skew = 3000
        }
      }

      local route3 = bp.routes:insert {
        hosts = { "hmacauth3.com" },
      }

      bp.plugins:insert {
        name     = "hmac-auth",
        route = { id = route3.id },
        config   = {
          anonymous  = utils.uuid(),  -- non existing consumer
          clock_skew = 3000
        }
      }

      local route4 = bp.routes:insert {
        hosts = { "hmacauth4.com" },
      }

      bp.plugins:insert {
        name     = "hmac-auth",
        route = { id = route4.id },
        config   = {
          clock_skew            = 3000,
          validate_request_body = true
        }
      }

      local route5 = bp.routes:insert {
        hosts = { "hmacauth5.com" },
      }

      bp.plugins:insert {
        name     = "hmac-auth",
        route = { id = route5.id },
        config   = {
          clock_skew            = 3000,
          enforce_headers       = {"date", "request-line"},
          validate_request_body = true
        }
      }

      local route6 = bp.routes:insert {
        hosts = { "hmacauth6.com" },
      }

      bp.plugins:insert {
        name     = "hmac-auth",
        route = { id = route6.id },
        config   = {
          clock_skew            = 3000,
          enforce_headers       = {"date", "request-line"},
          algorithms            = {"hmac-sha1", "hmac-sha256"},
          validate_request_body = true
        }
      }

      local route7 = bp.routes:insert {
        hosts = { "hmacauth7.com" },
      }

      bp.plugins:insert {
        name     = "hmac-auth",
        route = { id = route7.id },
        config   = {
          anonymous  = anonymous_user.username,
          clock_skew = 3000
        }
      }

      assert(helpers.start_kong {
        database          = strategy,
        real_ip_header    = "X-Forwarded-For",
        real_ip_recursive = "on",
        trusted_ips       = "0.0.0.0/0, ::/0",
        nginx_conf        = "spec/fixtures/custom_nginx.template",
      })

      proxy_client = helpers.proxy_client()
    end)

    lazy_teardown(function()
      if proxy_client then
        proxy_client:close()
      end

      helpers.stop_kong()
    end)

    describe("HMAC Authentication", function()
      it("should not be authorized when the hmac credentials are missing", function()
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
        local res = assert(proxy_client:send {
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
        local res = assert(proxy_client:send {
          method = "POST",
          body = {},
          headers = {
            ["HOST"] = "hmacauth.com",
            date = date,
            authorization = "asd"
          }
        })
        local body = assert.res_status(401, res)
        body = cjson.decode(body)
        assert.equal(SIGNATURE_NOT_VALID, body.message)
      end)

      it("should not be authorized when the HMAC signature is not properly base64 encoded", function()
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
        local hmacAuth = [["hmac username="bob",algorithm="hmac-sha1",]]
          .. [[headers="date",signature="not really a base64 encoded value!!!"]]
        local res  = assert(proxy_client:send {
          method          = "POST",
          headers         = {
            ["HOST"]      = "hmacauth.com",
            date          = date,
            authorization = hmacAuth
          }
        })
        local body = assert.res_status(401, res)
        body = cjson.decode(body)
        assert.equal("HMAC signature does not match", body.message)
      end)

      it("should not be authorized when date header is missing", function()
        local res = assert(proxy_client:send {
          method = "POST",
          body = {},
          headers = {
            ["HOST"] = "hmacauth.com",
            authorization = "asd"
          }
        })
        local body = assert.res_status(401, res)
        body = cjson.decode(body)
        assert.equal([[HMAC signature cannot be verified, ]]
                    .. [[a valid date or x-date header is]]
                    .. [[ required for HMAC Authentication]], body.message)
      end)

      it("should not be authorized with signature is wrong in proxy-authorization", function()
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
        local res = assert(proxy_client:send {
          method = "POST",
          body = {},
          headers = {
            ["HOST"] = "hmacauth.com",
            date = date,
            ["proxy-authorization"] = "asd"
          }
        })
        local body = assert.res_status(401, res)
        body = cjson.decode(body)
        assert.equal(SIGNATURE_NOT_VALID, body.message)
      end)

      it("should not pass when passing only the digest", function()
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
        local res = assert(proxy_client:send {
          method = "POST",
          body = {},
          headers = {
            ["HOST"] = "hmacauth.com",
            date = date,
            ["proxy-authorization"] = "hmac :dXNlcm5hbWU6cGFzc3dvcmQ="
          }
        })
        local body = assert.res_status(401, res)
        body = cjson.decode(body)
        assert.equal(SIGNATURE_NOT_VALID, body.message)
      end)

      it("should not pass when passing wrong hmac parameters", function()
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
        local res = assert(proxy_client:send {
          method = "POST",
          body = {},
          headers = {
            ["HOST"] = "hmacauth.com",
            date = date,
            ["proxy-authorization"] = [[hmac username=,algorithm,]]
              .. [[headers,dXNlcm5hbWU6cGFzc3dvcmQ=]]
          }
        })
        local body = assert.res_status(401, res)
        body = cjson.decode(body)
        assert.equal(SIGNATURE_NOT_VALID, body.message)
      end)

      it("should not pass when passing wrong hmac parameters", function()
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
        local res = assert(proxy_client:send {
          method = "POST",
          body = {},
          headers = {
            ["HOST"] = "hmacauth.com",
            date = date,
            authorization = [[hmac username=,algorithm,]]
              .. [[headers,dXNlcm5hbWU6cGFzc3dvcmQ=]]
          }
        })
        local body = assert.res_status(401, res)
        body = cjson.decode(body)
        assert.equal(SIGNATURE_NOT_VALID, body.message)
      end)

      it("should not be authorized when passing only the username", function()
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
        local res = assert(proxy_client:send {
          method = "POST",
          body = {},
          headers = {
            ["HOST"] = "hmacauth.com",
            date = date,
            authorization = "hmac username"
          }
        })
        local body = assert.res_status(401, res)
        body = cjson.decode(body)
        assert.equal(SIGNATURE_NOT_VALID, body.message)
      end)

      it("should not be authorized when authorization header is missing", function()
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
        local res = assert(proxy_client:send {
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
        local encodedSignature   = ngx.encode_base64(hmac_sha1_binary("secret", "date: " .. date))
        local hmacAuth = [[hmac username="bob",algorithm="hmac-sha1",]]
          .. [[headers="date",signature="]] .. encodedSignature .. [["]]
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          body    = {},
          headers = {
            ["HOST"]      = "hmacauth.com",
            date          = date,
            authorization = hmacAuth,
          },
        })
        local body = assert.res_status(200, res)
        body = cjson.decode(body)
        assert.equal(hmacAuth, body.headers["authorization"])
      end)

      it("should pass with GET and proxy-authorization", function()
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
        local encodedSignature   = ngx.encode_base64(hmac_sha1_binary("secret", "date: " .. date))
        local hmacAuth = [[hmac username="bob",algorithm="hmac-sha1",]]
          .. [[headers="date",signature="]] .. encodedSignature .. [["]]
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          body    = {},
          headers = {
            ["HOST"]                = "hmacauth.com",
            date                    = date,
            ["proxy-authorization"] = hmacAuth,
          },
        })
        assert.res_status(200, res)
      end)

      it("should pass with POST", function()
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
        local encodedSignature   = ngx.encode_base64(hmac_sha1_binary("secret", "date: " .. date))
        local hmacAuth = [[hmac username="bob",algorithm="hmac-sha1",]]
          .. [[headers="date",signature="]] .. encodedSignature .. [["]]
        local res = assert(proxy_client:send {
          method  = "POST",
          path    = "/request",
          body    = {},
          headers = {
            ["HOST"]      = "hmacauth.com",
            date          = date,
            authorization = hmacAuth,
          },
        })
        local body = assert.res_status(200, res)
        body = cjson.decode(body)
        assert.equal(hmacAuth, body.headers["authorization"])
      end)

      it("should pass with GET and valid authorization and wrong proxy-authorization", function()
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
        local encodedSignature   = ngx.encode_base64(hmac_sha1_binary("secret", "date: " .. date))
        local hmacAuth = [[hmac username="bob",algorithm="hmac-sha1",]]
          .. [[headers="date",signature="]] .. encodedSignature .. [["]]
        local res = assert(proxy_client:send {
          method  = "POST",
          path    = "/request",
          body    = {},
          headers = {
            ["HOST"]                = "hmacauth.com",
            date                    = date,
            ["proxy-authorization"] = "hmac username",
            authorization           = hmacAuth,
          },
        })
        local body = assert.res_status(200, res)
        body = cjson.decode(body)
        assert.equal(hmacAuth, body.headers["authorization"])
      end)

      it("should pass with GET and invalid authorization and valid proxy-authorization", function()
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
        local encodedSignature   = ngx.encode_base64(
          hmac_sha1_binary("secret", "date: " .. date))
        local hmacAuth = [[hmac username="bob",algorithm="hmac-sha1",]]
          .. [[headers="date",signature="]] .. encodedSignature .. [["]]
        local res = assert(proxy_client:send {
          method  = "POST",
          path    = "/request",
          body    = {},
          headers = {
            ["HOST"]                = "hmacauth.com",
            date                    = date,
            ["proxy-authorization"] = hmacAuth,
            authorization           = "hello",
          },
        })
        assert.res_status(200, res)
      end)

      it("should pass with GET with content-md5 header", function()
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
        local encodedSignature = ngx.encode_base64(
          hmac_sha1_binary("secret", "date: " .. date .. "\n" .. "content-md5: md5"))
        local hmacAuth = [[hmac username="bob",algorithm="hmac-sha1",]]
          .. [[headers="date content-md5",signature="]] .. encodedSignature .. [["]]
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          body    = {},
          headers = {
            ["HOST"]                = "hmacauth.com",
            date                    = date,
            ["proxy-authorization"] = hmacAuth,
            authorization           = "hello",
            ["content-md5"]         = "md5",
          },
        })
        assert.res_status(200, res)
      end)

      it("should pass with GET with request-line", function()
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
        local encodedSignature = ngx.encode_base64(
          hmac_sha1_binary("secret", "date: "
            .. date .. "\n" .. "content-md5: md5" .. "\nGET /request HTTP/1.1"))
        local hmacAuth = [[hmac username="bob",  algorithm="hmac-sha1", ]]
          .. [[headers="date content-md5 request-line", signature="]]
          .. encodedSignature .. [["]]
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          body    = {},
          headers = {
            ["HOST"]                = "hmacauth.com",
            date                    = date,
            ["proxy-authorization"] = hmacAuth,
            authorization           = "hello",
            ["content-md5"]         = "md5",
          },
        })
        assert.res_status(200, res)
      end)

      it("should encode http-1 requests as http/1.0", function()
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
        local encodedSignature = ngx.encode_base64(
          hmac_sha1_binary("secret", "date: "
            .. date .. "\n" .. "content-md5: md5" .. "\nGET /request HTTP/1.0"))
        local hmacAuth = [[hmac username="bob",  algorithm="hmac-sha1", ]]
          .. [[headers="date content-md5 request-line", signature="]]
          .. encodedSignature .. [["]]
        local res = assert(proxy_client:send {
          version = 1.0,
          method  = "GET",
          path    = "/request",
          body    = {},
          headers = {
            ["HOST"]                = "hmacauth.com",
            date                    = date,
            ["proxy-authorization"] = hmacAuth,
            authorization           = "hello",
            ["content-md5"]         = "md5",
          },
        })
        assert.res_status(200, res)
      end)


      it("should not pass with GET with wrong username in signature", function()
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
        local encodedSignature = ngx.encode_base64(
          hmac_sha1_binary("secret", "date: " .. date .. "\n"
          .. "content-md5: md5" .. "\nGET /request HTTP/1.1"))
        local hmacAuth = [[hmac username="bobb",  algorithm="hmac-sha1", ]]
          .. [[headers="date content-md5 request-line", signature="]]
          .. encodedSignature .. [["]]
            local res = assert(proxy_client:send {
              method  = "GET",
              path    = "/request",
              body    = {},
              headers = {
                ["HOST"]                = "hmacauth.com",
                date                    = date,
                ["proxy-authorization"] = hmacAuth,
                authorization           = "hello",
                ["content-md5"]         = "md5",
              },
            })

        local body = assert.res_status(401, res)
        body = cjson.decode(body)
        assert.equal(SIGNATURE_NOT_VALID, body.message)
      end)

      it("should not pass with GET with username blank in signature", function()
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
        local encodedSignature = ngx.encode_base64(
          hmac_sha1_binary("secret",
            "date: " .. date .. "\n" .. "content-md5: md5" .. "\nGET /request HTTP/1.1"))
        local hmacAuth = [[hmac username="",  algorithm="hmac-sha1",]]
          .. [[ headers="date content-md5 request-line", signature="]]
          .. encodedSignature .. [["]]
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          body    = {},
          headers = {
            ["HOST"]                = "hmacauth.com",
            date                    = date,
            ["proxy-authorization"] = hmacAuth,
            authorization           = "hello",
            ["content-md5"]         = "md5",
          },
        })

        local body = assert.res_status(401, res)
        body = cjson.decode(body)
        assert.equal(SIGNATURE_NOT_VALID, body.message)
      end)

      it("should not pass with GET with username missing in signature", function()
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
        local encodedSignature = ngx.encode_base64(
          hmac_sha1_binary("secret",
            "date: " .. date .. "\n" .. "content-md5: md5"
            .. "\nGET /request HTTP/1.1"))
        local hmacAuth = [[hmac algorithm="hmac-sha1", ]]
          .. [[headers="date content-md5 request-line", signature="]]
          .. encodedSignature .. [["]]
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          body    = {},
          headers = {
            ["HOST"]                = "hmacauth.com",
            date                    = date,
            ["proxy-authorization"] = hmacAuth,
            authorization           = "hello",
            ["content-md5"]         = "md5",
          },
        })

        local body = assert.res_status(401, res)
        body = cjson.decode(body)
        assert.equal(SIGNATURE_NOT_VALID, body.message)
      end)

      it("should not pass with GET with wrong hmac headers field name", function()
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
        local encodedSignature = ngx.encode_base64(
          hmac_sha1_binary("secret", "date: " .. date .. "\n"
            .. "content-md5: md5" .. "\nGET /request HTTP/1.1"))
        local hmacAuth = [[hmac username="bob",  algorithm="hmac-sha1",   ]]
          .. [[wrong_header="date content-md5 request-line", signature="]]
          .. encodedSignature .. [["]]
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          body    = {},
          headers = {
            ["HOST"]                = "hmacauth.com",
            date                    = date,
            ["proxy-authorization"] = hmacAuth,
            authorization           = "hello",
            ["content-md5"]         = "md5",
          },
        })
        local body = assert.res_status(401, res)
        body = cjson.decode(body)
        assert.equal(SIGNATURE_NOT_VALID, body.message)
      end)

       it("should not pass with GET with wrong hmac signature field name", function()
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
        local encodedSignature = ngx.encode_base64(
          hmac_sha1_binary("secret", "date: " .. date .. "\n"
            .. "content-md5: md5" .. "\nGET /request HTTP/1.1"))
        local hmacAuth = [[hmac username="bob",  algorithm="hmac-sha1",]]
          .. [[   headers="date content-md5 request-line", wrong_signature="]]
          .. encodedSignature .. [["]]
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          body    = {},
          headers = {
            ["HOST"]                = "hmacauth.com",
            date                    = date,
            ["proxy-authorization"] = hmacAuth,
            authorization           = "hello",
            ["content-md5"]         = "md5",
          },
        })
        local body = assert.res_status(401, res)
        body = cjson.decode(body)
        assert.equal(SIGNATURE_NOT_VALID, body.message)
      end)

      it("should not pass with GET with malformed hmac signature field", function()
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
        local encodedSignature = ngx.encode_base64(
          hmac_sha1_binary("secret", "date: " .. date .. "\n"
            .. "content-md5: md5" .. "\nGET /request HTTP/1.1"))
        local hmacAuth = [[hmac username="bob",  algorithm="hmac-sha1"]]
          .. [[ headers="date content-md5 request-line", signature="]]
          .. encodedSignature .. [["]]
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          body    = {},
          headers = {
            ["HOST"]                = "hmacauth.com",
            date                    = date,
            ["proxy-authorization"] = hmacAuth,
            authorization           = "hello",
            ["content-md5"]         = "md5",
          },
        })
        local body = assert.res_status(401, res)
        body = cjson.decode(body)
        assert.equal(SIGNATURE_NOT_VALID, body.message)
      end)

      it("should not pass with GET with malformed hmac headers field", function()
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
        local encodedSignature = ngx.encode_base64(
          hmac_sha1_binary("secret", "date: " .. date .. "\n"
            .. "content-md5: md5" .. "\nGET /request? HTTP/1.1"))
        local hmacAuth = [[hmac username="bob",  algorithm="hmac-sha1" ]]
          .. [[headers="  date content-md5 request-line",signature="]]
          .. encodedSignature .. [["]]
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          body    = {},
          headers                   = {
            ["HOST"]                = "hmacauth.com",
            date                    = date,
            ["proxy-authorization"] = hmacAuth,
            authorization           = "hello",
            ["content-md5"]         = "md5",
          },
        })
        local body = assert.res_status(401, res)
        body = cjson.decode(body)
        assert.equal(SIGNATURE_NOT_VALID, body.message)
      end)

      it("should pass with GET with no space or space between hmac signatures fields", function()
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
        local encodedSignature = ngx.encode_base64(
        hmac_sha1_binary("secret", "date: " .. date .. "\n"
          .. "content-md5: md5" .. "\nGET /request HTTP/1.1"))
        local hmacAuth = [[hmac username="bob",algorithm="hmac-sha1",]]
          .. [[  headers="date content-md5 request-line",signature="]]
          .. encodedSignature .. [["]]
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          body    = {},
          headers = {
            ["HOST"]                = "hmacauth.com",
            date                    = date,
            ["proxy-authorization"] = hmacAuth,
            authorization           = "hello",
            ["content-md5"]         = "md5",
          },
        })
        assert.res_status(200, res)
      end)

      it("should not pass with GET with wrong algorithm", function()
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
        local encodedSignature = ngx.encode_base64(
          openssl_hmac.new("secret", "sha256"):final("date: " .. date .. "\n"
            .. "content-md5: md5" .. "\nGET /request HTTP/1.1"))
        local hmacAuth = [[hmac username="bob",algorithm="hmac-sha",]]
          .. [[  headers="date content-md5 request-line",signature="]]
          .. encodedSignature .. [["]]
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          body    = {},
          headers = {
            ["HOST"]                = "hmacauth.com",
            date                    = date,
            ["proxy-authorization"] = hmacAuth,
            authorization           = "hello",
            ["content-md5"]         = "md5",
          },
        })
        assert.res_status(401, res)
      end)

      it("should pass the right headers to the upstream server", function()
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
        local encodedSignature = ngx.encode_base64(
          openssl_hmac.new("secret", "sha256"):final("date: " .. date .. "\n"
                             .. "content-md5: md5" .. "\nGET /request HTTP/1.1"))
        local hmacAuth = [[hmac username="bob",algorithm="hmac-sha256",]]
          .. [[  headers="date content-md5 request-line",signature="]]
          .. encodedSignature .. [["]]
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          body    = {},
          headers = {
            ["HOST"]                = "hmacauth.com",
            date                    = date,
            ["proxy-authorization"] = hmacAuth,
            authorization           = "hello",
            ["content-md5"]         = "md5",
          },
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
          hmac_sha1_binary("secret", "x-date: " .. date .. "\n"
            .. "content-md5: md5" .. "\nGET /request HTTP/1.1"))
        local hmacAuth = [[hmac username="bob",algorithm="hmac-sha1",]]
          .. [[  headers="x-date content-md5 request-line",signature="]]
          .. encodedSignature .. [["]]
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          body    = {},
          headers = {
            ["HOST"]        = "hmacauth.com",
            ["x-date"]      = date,
            authorization   = hmacAuth,
            ["content-md5"] = "md5",
          },
        })
        assert.res_status(200, res)
      end)

      it("should not pass with GET with both date and x-date missing", function()
        local encodedSignature = ngx.encode_base64(
          hmac_sha1_binary("secret", "content-md5: md5"
            .. "\nGET /request? HTTP/1.1"))
        local hmacAuth = [[hmac username="bob",  algorithm="hmac-sha1",]]
          .. [[ headers="content-md5 request-line",signature="]]
          .. encodedSignature .. [["]]
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          body    = {},
          headers = {
            ["HOST"]                = "hmacauth.com",
            ["proxy-authorization"] = hmacAuth,
            authorization           = "hello",
            ["content-md5"]         = "md5",
          },
        })
        local body = assert.res_status(401, res)
        body = cjson.decode(body)
        assert.equal([[HMAC signature cannot be verified, a valid date or]]
          .. [[ x-date header is required for HMAC Authentication]], body.message)
      end)

      it("should not pass with GET with x-date malformed", function()
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
        local encodedSignature = ngx.encode_base64(
          hmac_sha1_binary("secret", "x-date: " .. date .. "\n"
            .. "content-md5: md5" .. "\nGET /request? HTTP/1.1"))
        local hmacAuth = [[hmac username="bob",algorithm="hmac-sha1",]]
          .. [[  headers="x-date content-md5 request-line",signature="]]
          .. encodedSignature .. [["]]
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          body    = {},
          headers = {
            ["HOST"]        = "hmacauth.com",
            ["x-date"]      = "wrong date",
            authorization   = hmacAuth,
            ["content-md5"] = "md5",
          },
        })
        local body = assert.res_status(401, res)
        body = cjson.decode(body)
        assert.equal([[HMAC signature cannot be verified, a valid date or]]
          .. [[ x-date header is required for HMAC Authentication]], body.message)
      end)

      it("should pass with GET with x-date malformed but date correct", function()
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
        local encodedSignature = ngx.encode_base64(
          hmac_sha1_binary("secret", "content-md5: md5"
            .. "\nGET /request HTTP/1.1"))
        local hmacAuth = [[hmac username="bob",algorithm="hmac-sha1",]]
          .. [[  headers="content-md5 request-line",signature="]]
          .. encodedSignature .. [["]]
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          body    = {},
          headers = {
            ["HOST"]        = "hmacauth.com",
            ["x-date"]      = "wrong date",
            date            = date,
            authorization   = hmacAuth,
            ["content-md5"] = "md5",
          },
        })
        assert.res_status(200, res)
      end)

      it("should pass with x-date malformed but date correct and used for signature", function()
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
        local encodedSignature = ngx.encode_base64(
          hmac_sha1_binary("secret", "date: " .. date .. "\n"
            .. "content-md5: md5" .. "\nGET /request HTTP/1.1"))
        local hmacAuth = [[hmac username="bob",algorithm="hmac-sha1",]]
          .. [[  headers="date content-md5 request-line",signature="]]
          .. encodedSignature .. [["]]
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          body    = {},
          headers = {
            ["HOST"]        = "hmacauth.com",
            ["x-date"]      = "wrong date",
            date            = date,
            authorization   = hmacAuth,
            ["content-md5"] = "md5",
          },
        })
        assert.res_status(200, res)
      end)

      it("should with x-date malformed and used for signature but skew test pass", function()
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
        local encodedSignature = ngx.encode_base64(
          hmac_sha1_binary("secret", "x-date: " .. "wrong date" .. "\n"
            .. "content-md5: md5" .. "\nGET /request HTTP/1.1"))
        local hmacAuth = [[hmac username="bob",algorithm="hmac-sha1",]]
          .. [[  headers="x-date content-md5 request-line",signature="]]
          .. encodedSignature .. [["]]
              local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          body    = {},
          headers = {
            ["HOST"]        = "hmacauth.com",
            ["x-date"]      = "wrong date",
            date            = date,
            authorization   = hmacAuth,
            ["content-md5"] = "md5",
          },
        })
        assert.res_status(200, res)
      end)

      it("should pass with date malformed and used for signature but skew test pass", function()
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
        local encodedSignature = ngx.encode_base64(
          hmac_sha1_binary("secret", "date: " .. "wrong date" .. "\n"
            .. "content-md5: md5" .. "\nGET /request HTTP/1.1"))
        local hmacAuth = [[hmac username="bob",algorithm="hmac-sha1",]]
          .. [[  headers="date content-md5 request-line",signature="]]
          .. encodedSignature .. [["]]
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          body    = {},
          headers = {
            ["HOST"]        = "hmacauth.com",
            ["x-date"]      = date,
            date            = "wrong date",
            authorization   = hmacAuth,
            ["content-md5"] = "md5",
          }
        })
        assert.res_status(200, res)
      end)

      it("should pass with valid credentials and anonymous", function()
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
        local encodedSignature   = ngx.encode_base64(hmac_sha1_binary("secret", "date: " .. date))
        local hmacAuth = [[hmac username="bob",algorithm="hmac-sha1",]]
          .. [[headers="date",signature="]] .. encodedSignature .. [["]]
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          body    = {},
          headers = {
            ["HOST"]      = "hmacauth2.com",
            date          = date,
            authorization = hmacAuth,
          },
        })
        local body = assert.res_status(200, res)
        body = cjson.decode(body)
        assert.equal(hmacAuth, body.headers["authorization"])
        assert.equal("bob", body.headers["x-consumer-username"])
        assert.is_nil(body.headers["x-anonymous-consumer"])
      end)

      it("should return 401 when body validation enabled and no digest header is present", function()
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
        local postBody = '{"a":"apple","b":"ball"}'
        local sha256 = resty_sha256:new()
        sha256:update(postBody)

        local encodedSignature   = ngx.encode_base64(
          hmac_sha1_binary("secret", "date: "..date))
        local hmacAuth = [["hmac username="bob",algorithm="hmac-sha1",]]
                ..[[headers="date",signature="]]..encodedSignature..[["]]
        local res = assert(proxy_client:send {
          method  = "POST",
          path    = "/request",
          body    = postBody,
          headers = {
            ["HOST"]      = "hmacauth4.com",
            date          = date,
            authorization = hmacAuth,
          }
        })
        local body = assert.res_status(401, res)
        body = cjson.decode(body)
        assert.equal("HMAC signature does not match", body.message)
      end)

      it("should return 200 when body validation enabled and no body and no digest header is present", function()
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")

        local encodedSignature   = ngx.encode_base64(
          hmac_sha1_binary("secret", "date: "..date))
        local hmacAuth = [["hmac username="bob",algorithm="hmac-sha1",]]
                ..[[headers="date",signature="]]..encodedSignature..[["]]
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["HOST"]      = "hmacauth4.com",
            date          = date,
            authorization = hmacAuth,
          }
        })
        assert.res_status(200, res)
      end)

      it("should return 200 when body validation enabled and no body and an digest header is present", function()
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
        local sha256 = resty_sha256:new()
        sha256:update('')
        local digest = "SHA-256=" .. ngx.encode_base64(sha256:final())

        local encodedSignature   = ngx.encode_base64(
          hmac_sha1_binary("secret", "date: "..date.."\n".."digest: "..digest))
        local hmacAuth = [["hmac username="bob",algorithm="hmac-sha1",]]
                ..[[headers="date digest",signature="]]..encodedSignature..[["]]
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["HOST"]      = "hmacauth4.com",
            date          = date,
            digest        = digest,
            authorization = hmacAuth,
          }
        })
        assert.res_status(200, res)
      end)

      it("should pass with invalid credentials and anonymous", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          body    = {},
          headers = {
            ["HOST"] = "hmacauth2.com",
          },
        })
        local body = assert.res_status(200, res)
        body = cjson.decode(body)
        assert.equal("true", body.headers["x-anonymous-consumer"])
        assert.equal('no-body', body.headers["x-consumer-username"])
      end)

      it("should pass with invalid credentials and username in anonymous", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          body    = {},
          headers = {
            ["HOST"] = "hmacauth7.com",
          },
        })
        local body = assert.res_status(200, res)
        body = cjson.decode(body)
        assert.equal("true", body.headers["x-anonymous-consumer"])
        assert.equal('no-body', body.headers["x-consumer-username"])
      end)

      it("errors when anonymous user doesn't exist", function()
        finally(function()
          proxy_client = helpers.proxy_client()
        end)

        local res = assert(proxy_client:send {
          method = "GET",
          path    = "/request",
          headers = {
            ["Host"] = "hmacauth3.com",
          },
        })
        assert.response(res).has.status(500)
      end)

      it("should pass with GET when body validation enabled", function()
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
        local encodedSignature   = ngx.encode_base64(hmac_sha1_binary("secret", "date: "..date))
        local hmacAuth = [["hmac username="bob",algorithm="hmac-sha1",]]
                ..[[headers="date",signature="]]..encodedSignature..[["]]
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          body    = {},
          headers = {
            ["HOST"]      = "hmacauth4.com",
            date          = date,
            authorization = hmacAuth,
          },
        })
        assert.res_status(200, res)
      end)

      it("should pass with POST when body validation enabled and digest header present", function()
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
        local postBody = '{"a":"apple","b":"ball"}'
        local sha256 = resty_sha256:new()
        sha256:update(postBody)
        local digest = "SHA-256=" .. ngx.encode_base64(sha256:final())

        local encodedSignature   = ngx.encode_base64(
          hmac_sha1_binary("secret", "date: "..date.."\n".."digest: "..digest))
        local hmacAuth = [["hmac username="bob",algorithm="hmac-sha1",]]
                ..[[headers="date digest",signature="]]..encodedSignature..[["]]
        local res = assert(proxy_client:send {
          method  = "POST",
          path    = "/request",
          body    = postBody,
          headers = {
            ["HOST"]      = "hmacauth4.com",
            date          = date,
            digest        = digest,
            authorization = hmacAuth,
          },
        })
        assert.res_status(200, res)
      end)

      it("should pass with POST when body validation enabled but digest header not used", function()
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
        local postBody = '{"a":"apple","b":"ball"}'
        local sha256 = resty_sha256:new()
        sha256:update(postBody)
        local digest = "SHA-256=" .. ngx.encode_base64(sha256:final())

        local encodedSignature   = ngx.encode_base64(
          hmac_sha1_binary("secret", "date: "..date.."\n".."digest: "..digest))
        local hmacAuth = [["hmac username="bob",algorithm="hmac-sha1",]]
                ..[[headers="date digest",signature="]]..encodedSignature..[["]]
        local res = assert(proxy_client:send {
          method  = "POST",
          path    = "/request",
          body    = postBody,
          headers = {
            ["HOST"]      = "hmacauth4.com",
            date          = date,
            digest        = digest,
            authorization = hmacAuth,
          },
        })
        assert.res_status(200, res)
      end)

      it("should not pass with POST when body validation enabled and digest header missing", function()
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
        local postBody = '{"a":"apple","b":"ball"}'
        local sha256 = resty_sha256:new()
        sha256:update(postBody)
        local digest = "SHA-256=" .. ngx.encode_base64(sha256:final())

        local encodedSignature   = ngx.encode_base64(
          hmac_sha1_binary("secret", "date: "..date.."\n".."digest: "..digest))
        local hmacAuth = [["hmac username="bob",algorithm="hmac-sha1",]]
                ..[[headers="date digest",signature="]]..encodedSignature..[["]]
        local res = assert(proxy_client:send {
          method  = "POST",
          path    = "/request",
          body    = postBody,
          headers = {
            ["HOST"]      = "hmacauth4.com",
            date          = date,
            authorization = hmacAuth,
          },
        })
        local body = assert.res_status(401, res)
        body = cjson.decode(body)
        assert.equal("HMAC signature does not match", body.message)
      end)

      it("should not pass with POST when body validation enabled and postBody is tampered", function()
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
        local postBody = '{"a":"apple","b":"ball"}'
        local sha256 = resty_sha256:new()
        sha256:update(postBody)
        local digest = "SHA-256=" .. ngx.encode_base64(sha256:final())

        local encodedSignature   = ngx.encode_base64(
          hmac_sha1_binary("secret", "date: "..date.."\n".."digest: "..digest))
        local hmacAuth = [["hmac username="bob",algorithm="hmac-sha1",]]
                ..[[headers="date digest",signature="]]..encodedSignature..[["]]
        local res = assert(proxy_client:send {
          method  = "POST",
          path    = "/request",
          body    = "abc",
          headers = {
            ["HOST"]      = "hmacauth4.com",
            date          = date,
            digest        = digest,
            authorization = hmacAuth,
          },
        })
        local body = assert.res_status(401, res)
        body = cjson.decode(body)
        assert.equal("HMAC signature does not match", body.message)
      end)

      it("should not pass with POST when body validation enabled and digest header is tampered", function()
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
        local postBody = '{"a":"apple","b":"ball"}'
        local sha256 = resty_sha256:new()
        sha256:update(postBody)
        local digest = "SHA-256=" .. ngx.encode_base64(sha256:final())

        local encodedSignature   = ngx.encode_base64(
          hmac_sha1_binary("secret", "date: "..date.."\n".."digest: "..digest))
        local hmacAuth = [["hmac username="bob",algorithm="hmac-sha1",]]
                ..[[headers="date digest",signature="]]..encodedSignature..[["]]
        local res = assert(proxy_client:send {
          method  = "POST",
          path    = "/request",
          body    = postBody,
          headers = {
            ["HOST"]      = "hmacauth4.com",
            date          = date,
            digest        = digest .. "spoofed",
            authorization = hmacAuth,
          }
        })
        local body = assert.res_status(401, res)
        body = cjson.decode(body)
        assert.equal("HMAC signature does not match", body.message)
      end)

      it("should pass with GET with request-line", function()
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
        local encodedSignature = ngx.encode_base64(
          hmac_sha1_binary("secret", "date: "
                  .. date .. "\n" .. "content-md5: md5" .. "\nGET /request HTTP/1.1"))
        local hmacAuth = [[hmac username="bob",  algorithm="hmac-sha1", ]]
                .. [[headers="date content-md5 request-line", signature="]]
                .. encodedSignature .. [["]]
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          body    = {},
          headers = {
            ["HOST"]                = "hmacauth5.com",
            date                    = date,
            ["proxy-authorization"] = hmacAuth,
            ["content-md5"]         = "md5",
          },
        })
        assert.res_status(200, res)
      end)

      it("should pass with GET with request-line having query param but signed without query param", function()
        -- hmac-auth needs to validate signatures created both with and without
        -- query params for a supported deprecation period.
        --
        -- Regression for https://github.com/Kong/kong/issues/3672
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
        local encodedSignature = ngx.encode_base64(
          hmac_sha1_binary("secret", "date: "
            .. date .. "\n" .. "content-md5: md5" .. "\nGET /request HTTP/1.1"))
        local hmacAuth = [[hmac username="bob",  algorithm="hmac-sha1", ]]
          .. [[headers="date content-md5 request-line", signature="]]
          .. encodedSignature .. [["]]
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request?name=foo",
          body    = {},
          headers = {
            ["HOST"]                = "hmacauth5.com",
            date                    = date,
            ["proxy-authorization"] = hmacAuth,
            ["content-md5"]         = "md5",
          },
        })
        assert.res_status(200, res)

        encodedSignature = ngx.encode_base64(
          hmac_sha1_binary("secret", "date: "
            .. date .. "\n" .. "content-md5: md5" .. "\nGET /request/ HTTP/1.1"))
        local hmacAuth = [[hmac username="bob",  algorithm="hmac-sha1", ]]
          .. [[headers="date content-md5 request-line", signature="]]
          .. encodedSignature .. [["]]
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request/?name=foo",
          body    = {},
          headers = {
            ["HOST"]                = "hmacauth5.com",
            date                    = date,
            ["proxy-authorization"] = hmacAuth,
            ["content-md5"]         = "md5",
          },
        })
        assert.res_status(200, res)
      end)

      it("should pass with GET with request-line having query param", function()
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
        local encodedSignature = ngx.encode_base64(
          hmac_sha1_binary("secret", "date: "
            .. date .. "\n" .. "content-md5: md5" .. "\nGET /request?name=foo HTTP/1.1"))
        local hmacAuth = [[hmac username="bob",  algorithm="hmac-sha1", ]]
          .. [[headers="date content-md5 request-line", signature="]]
          .. encodedSignature .. [["]]
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request?name=foo",
          body    = {},
          headers = {
            ["HOST"]                = "hmacauth5.com",
            date                    = date,
            ["proxy-authorization"] = hmacAuth,
            ["content-md5"]         = "md5",
          },
        })
        assert.res_status(200, res)

        encodedSignature = ngx.encode_base64(
          hmac_sha1_binary("secret", "date: "
            .. date .. "\n" .. "content-md5: md5" .. "\nGET /request/?name=foo HTTP/1.1"))
        local hmacAuth = [[hmac username="bob",  algorithm="hmac-sha1", ]]
          .. [[headers="date content-md5 request-line", signature="]]
          .. encodedSignature .. [["]]
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request/?name=foo",
          body    = {},
          headers = {
            ["HOST"]                = "hmacauth5.com",
            date                    = date,
            ["proxy-authorization"] = hmacAuth,
            ["content-md5"]         = "md5",
          },
        })
        assert.res_status(200, res)
      end)

      it("should pass with GET with request-line having encoded query param", function()
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
        local escaped_uri = fmt("/request?name=%s",
                                ngx.escape_uri("foo bar"))
        local encodedSignature = ngx.encode_base64(
          hmac_sha1_binary("secret", "date: "
            .. date .. "\n" .. "content-md5: md5" .. "\nGET " .. escaped_uri .. " HTTP/1.1"))
        local hmacAuth = [[hmac username="bob",  algorithm="hmac-sha1", ]]
          .. [[headers="date content-md5 request-line", signature="]]
          .. encodedSignature .. [["]]
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = escaped_uri,
          body    = {},
          headers = {
            ["HOST"]                = "hmacauth5.com",
            date                    = date,
            ["proxy-authorization"] = hmacAuth,
            ["content-md5"]         = "md5",
          },
        })
        local body = assert.res_status(200, res)
        local json_body = cjson.decode(body)
        assert.is.equal("foo bar", json_body.uri_args.name)

        local escaped_uri = fmt("/request?name=%s",
                                ngx.escape_uri("foo bár"))
        encodedSignature = ngx.encode_base64(
          hmac_sha1_binary("secret", "date: "
            .. date .. "\n" .. "content-md5: md5" .. "\nGET " .. escaped_uri .." HTTP/1.1"))
        local hmacAuth = [[hmac username="bob",  algorithm="hmac-sha1", ]]
          .. [[headers="date content-md5 request-line", signature="]]
          .. encodedSignature .. [["]]
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = escaped_uri,
          body    = {},
          headers = {
            ["HOST"]                = "hmacauth5.com",
            date                    = date,
            ["proxy-authorization"] = hmacAuth,
            ["content-md5"]         = "md5",
          },
        })
        local body = assert.res_status(200, res)
        local json_body = cjson.decode(body)
        assert.is.equal("foo bár", json_body.uri_args.name)
      end)

      it("should pass with GET with request-line having multiple query params", function()
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
        local escaped_uri = fmt("/request?name=%s&address=%s" ,
                                ngx.escape_uri("foo bar"),
                                ngx.escape_uri("san francisco"))
        local encodedSignature = ngx.encode_base64(
          hmac_sha1_binary("secret", "date: "
            .. date .. "\n" .. "content-md5: md5" .. "\nGET " .. escaped_uri .. " HTTP/1.1"))
        local hmacAuth = [[hmac username="bob",  algorithm="hmac-sha1", ]]
          .. [[headers="date content-md5 request-line", signature="]]
          .. encodedSignature .. [["]]
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = escaped_uri,
          body    = {},
          headers = {
            ["HOST"]                = "hmacauth5.com",
            date                    = date,
            ["proxy-authorization"] = hmacAuth,
            ["content-md5"]         = "md5",
          },
        })
        local body = assert.res_status(200, res)
        local json_body = cjson.decode(body)
        assert.is.equal("foo bar", json_body.uri_args.name)
        assert.is.equal("san francisco", json_body.uri_args.address)
      end)

      it("should pass with GET with request-line having multiple same query param", function()
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
        local encodedSignature = ngx.encode_base64(
          hmac_sha1_binary("secret", "date: "
            .. date .. "\n" .. "content-md5: md5" .. "\nGET /request?name=foo&name=bar HTTP/1.1"))
        local hmacAuth = [[hmac username="bob",  algorithm="hmac-sha1", ]]
          .. [[headers="date content-md5 request-line", signature="]]
          .. encodedSignature .. [["]]
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request?name=foo&name=bar",
          body    = {},
          headers = {
            ["HOST"]                = "hmacauth5.com",
            date                    = date,
            ["proxy-authorization"] = hmacAuth,
            ["content-md5"]         = "md5",
          },
        })
        local body = assert.res_status(200, res)
        local json_body = cjson.decode(body)
        assert.is.equal("foo", json_body.uri_args.name[1])
        assert.is.equal("bar", json_body.uri_args.name[2])
      end)

      it("should pass with GET with request-line having no uri", function()
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
        local encodedSignature = ngx.encode_base64(
          hmac_sha1_binary("secret", "date: "
            .. date .. "\n" .. "content-md5: md5" .. "\nGET / HTTP/1.1"))
        local hmacAuth = [[hmac username="bob",  algorithm="hmac-sha1", ]]
          .. [[headers="date content-md5 request-line", signature="]]
          .. encodedSignature .. [["]]
        local res = assert(proxy_client:send {
          method  = "GET",
          body    = {},
          headers = {
            ["HOST"]                = "hmacauth5.com",
            date                    = date,
            ["proxy-authorization"] = hmacAuth,
            ["content-md5"]         = "md5",
          },
        })
        assert.res_status(200, res)
      end)

      it("should pass with GET with request-line having encoded path param", function()
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
        local escaped_uri = fmt("/request/%s/?name=foo&name=bar",
                                ngx.escape_uri("some value"))
        local encodedSignature = ngx.encode_base64(
          hmac_sha1_binary("secret", "date: "
            .. date .. "\n" .. "content-md5: md5" .. "\nGET ".. escaped_uri .. " HTTP/1.1"))
        local hmacAuth = [[hmac username="bob",  algorithm="hmac-sha1", ]]
          .. [[headers="date content-md5 request-line", signature="]]
          .. encodedSignature .. [["]]
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = escaped_uri,
          body    = {},
          headers = {
            ["HOST"]                = "hmacauth5.com",
            date                    = date,
            ["proxy-authorization"] = hmacAuth,
            ["content-md5"]         = "md5",
          },
        })
        local body = assert.res_status(200, res)
        local json_body = cjson.decode(body)
        assert.is.equal("foo", json_body.uri_args.name[1])
        assert.is.equal("bar", json_body.uri_args.name[2])
        assert.is.equal("/request/some value/", json_body.vars.uri)
      end)

      it("should fail with GET when enforced header request-line missing", function()
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
        local encodedSignature = ngx.encode_base64(
          hmac_sha1_binary("secret", "date: "
                  .. date .. "\n" .. "content-md5: md5"))
        local hmacAuth = [[hmac username="bob",  algorithm="hmac-sha1", ]]
                .. [[headers="date content-md5", signature="]]
                .. encodedSignature .. [["]]
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          body    = {},
          headers = {
            ["HOST"]                = "hmacauth5.com",
            date                    = date,
            ["proxy-authorization"] = hmacAuth,
            ["content-md5"]         = "md5",
          },
        })
        assert.res_status(401, res)
      end)

      it("should pass with GET with hmac-sha384", function()
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
        local encodedSignature = ngx.encode_base64(
          openssl_hmac.new("secret", "sha384"):final("date: " .. date .. "\n"
                  .. "content-md5: md5" .. "\nGET /request HTTP/1.1"))
        local hmacAuth = [[hmac username="bob",  algorithm="hmac-sha384", ]]
                .. [[headers="date content-md5 request-line", signature="]]
                .. encodedSignature .. [["]]
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          body    = {},
          headers = {
            ["HOST"]                = "hmacauth5.com",
            date                    = date,
            ["proxy-authorization"] = hmacAuth,
            ["content-md5"]         = "md5",
          },
        })
        assert.res_status(200, res)
      end)

      it("should pass with GET with hmac-sha512", function()
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
        local encodedSignature = ngx.encode_base64(
          openssl_hmac.new("secret", "sha512"):final("date: " .. date .. "\n"
                  .. "content-md5: md5" .. "\nGET /request HTTP/1.1"))
        local hmacAuth = [[hmac username="bob",  algorithm="hmac-sha512", ]]
                .. [[headers="date content-md5 request-line", signature="]]
                .. encodedSignature .. [["]]
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          body    = {},
          headers = {
            ["HOST"]                = "hmacauth5.com",
            date                    = date,
            ["proxy-authorization"] = hmacAuth,
            ["content-md5"]         = "md5",
          },
        })
        assert.res_status(200, res)
      end)

      it("should not pass with hmac-sha512", function()
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
        local encodedSignature = ngx.encode_base64(
          openssl_hmac.new("secret", "sha512"):final("date: " .. date .. "\n"
                  .. "content-md5: md5" .. "\nGET /request HTTP/1.1"))
        local hmacAuth = [[hmac username="bob",  algorithm="hmac-sha512", ]]
                .. [[headers="date content-md5 request-line", signature="]]
                .. encodedSignature .. [["]]
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          body    = {},
          headers = {
            ["HOST"]                = "hmacauth6.com",
            date                    = date,
            ["proxy-authorization"] = hmacAuth,
            ["content-md5"]         = "md5",
          },
        })
        assert.res_status(401, res)
      end)

      it("should return a 401 with an invalid authorization header", function()
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          body    = {},
          headers = {
            ["HOST"]                = "hmacauth6.com",
            date                    = date,
            ["proxy-authorization"] = "this is no hmac token at all is it?",
          },
        })
        assert.res_status(401, res)
      end)

      it("should pass with hmac-sha1", function()
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
        local encodedSignature = ngx.encode_base64(
          openssl_hmac.new("secret", "sha1"):final("date: " .. date .. "\n"
                  .. "content-md5: md5" .. "\nGET /request HTTP/1.1"))
        local hmacAuth = [[hmac username="bob",  algorithm="hmac-sha1", ]]
                .. [[headers="date content-md5 request-line", signature="]]
                .. encodedSignature .. [["]]
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          body    = {},
          headers = {
            ["HOST"]                = "hmacauth6.com",
            date                    = date,
            ["proxy-authorization"] = hmacAuth,
            ["content-md5"]         = "md5",
          },
        })
        assert.res_status(200, res)
      end)

    end)
  end)

  describe("Plugin: hmac-auth (access) [#" .. strategy .. "]", function()
    local proxy_client
    local user1
    local user2
    local anonymous
    local hmacAuth
    local hmacDate

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "consumers",
        "plugins",
        "hmacauth_credentials",
        "keyauth_credentials",
      })

      local service1 = bp.services:insert({
        path = "/request"
      })

      local route1 = bp.routes:insert {
        hosts      = { "logical-and.com" },
        protocols  = { "http", "https" },
        service    = service1
      }

      bp.plugins:insert {
        name     = "hmac-auth",
        route = { id = route1.id }
      }

      bp.plugins:insert {
        name     = "key-auth",
        route = { id = route1.id }
      }

      anonymous = bp.consumers:insert {
        username = "Anonymous"
      }

      user1 = bp.consumers:insert {
        username = "Mickey"
      }

      user2 = bp.consumers:insert {
        username = "Aladdin"
      }

      local service2 = bp.services:insert({
        path = "/request"
      })

      local route2 = bp.routes:insert {
        hosts      = { "logical-or.com" },
        protocols  = { "http", "https" },
        service    = service2
      }

      bp.plugins:insert {
        name     = "hmac-auth",
        route = { id = route2.id },
        config   = {
          anonymous = anonymous.id
        }
      }

      bp.plugins:insert {
        name     = "key-auth",
        route = { id = route2.id },
        config   = {
          anonymous = anonymous.id
        }
      }

      bp.keyauth_credentials:insert {
        key      = "Mouse",
        consumer = { id = user1.id },
      }

      local credential = bp.hmacauth_credentials:insert {
        username = "Aladdin",
        secret   = "OpenSesame",
        consumer = { id = user2.id },
      }

      hmacDate = os.date("!%a, %d %b %Y %H:%M:%S GMT")
      local encodedSignature   = ngx.encode_base64(hmac_sha1_binary(credential.secret, "date: " .. hmacDate))
      hmacAuth = [[hmac username="]] .. credential.username .. [[",algorithm="hmac-sha1",]]
        .. [[headers="date",signature="]] .. encodedSignature .. [["]]

      assert(helpers.start_kong({
        database = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
      proxy_client = helpers.proxy_client()
    end)


    lazy_teardown(function()
      if proxy_client then proxy_client:close() end
      helpers.stop_kong()
    end)

    describe("multiple auth without anonymous, logical AND", function()

      it("passes with all credentials provided", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Host"]          = "logical-and.com",
            ["apikey"]        = "Mouse",
            ["Authorization"] = hmacAuth,
            ["date"]          = hmacDate,
          },
        })
        assert.response(res).has.status(200)
        assert.request(res).has.no.header("x-anonymous-consumer")
        local id = assert.request(res).has.header("x-consumer-id")
        assert.not_equal(id, anonymous.id)
        assert(id == user1.id or id == user2.id,
               string.format("expected %s or %s, got %s", user1.id, user2.id, id))
      end)

      it("fails 401, with only the first credential provided", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Host"]   = "logical-and.com",
            ["apikey"] = "Mouse",
          },
        })
        assert.response(res).has.status(401)
      end)

      it("fails 401, with only the second credential provided", function()
        local res = assert(proxy_client:send {
          method = "GET",
          path   = "/request",
          headers = {
            ["Host"]          = "logical-and.com",
            ["Authorization"] = hmacAuth,
            ["date"]          = hmacDate,
          },
        })
        assert.response(res).has.status(401)
      end)

      it("fails 401, with no credential provided", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Host"] = "logical-and.com",
          },
        })
        assert.response(res).has.status(401)
      end)

    end)

    describe("multiple auth with anonymous, logical OR", function()

      it("passes with all credentials provided", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Host"]          = "logical-or.com",
            ["apikey"]        = "Mouse",
            ["Authorization"] = hmacAuth,
            ["date"]          = hmacDate,
          },
        })
        assert.response(res).has.status(200)
        assert.request(res).has.no.header("x-anonymous-consumer")
        local id = assert.request(res).has.header("x-consumer-id")
        assert.not_equal(id, anonymous.id)
        assert(id == user1.id or id == user2.id,
               string.format("expected %s or %s, got %s", user1.id, user2.id, id))
      end)

      it("passes with only the first credential provided", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Host"]   = "logical-or.com",
            ["apikey"] = "Mouse",
          },
        })
        assert.response(res).has.status(200)
        assert.request(res).has.no.header("x-anonymous-consumer")
        local id = assert.request(res).has.header("x-consumer-id")
        assert.not_equal(id, anonymous.id)
        assert.equal(user1.id, id)
      end)

      it("passes with only the second credential provided", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Host"]          = "logical-or.com",
            ["Authorization"] = hmacAuth,
            ["date"]          = hmacDate,
          },
        })
        assert.response(res).has.status(200)
        assert.request(res).has.no.header("x-anonymous-consumer")
        local id = assert.request(res).has.header("x-consumer-id")
        assert.not_equal(id, anonymous.id)
        assert.equal(user2.id, id)
      end)

      it("passes with no credential provided", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Host"] = "logical-or.com",
          },
        })
        assert.response(res).has.status(200)
        assert.request(res).has.header("x-anonymous-consumer")
        local id = assert.request(res).has.header("x-consumer-id")
        assert.equal(id, anonymous.id)
      end)

    end)

  end)

end
