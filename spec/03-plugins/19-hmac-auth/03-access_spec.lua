local cjson = require "cjson"
local openssl_mac = require "resty.openssl.mac"
local helpers = require "spec.helpers"
local uuid = require "kong.tools.uuid"
local resty_sha256 = require "resty.sha256"

local fmt = string.format


local hmac_sha1_binary = function(secret, data)
  return openssl_mac.new(secret, "HMAC", nil, "sha1"):final(data)
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
        hosts = { "hmacauth.test" },
      }

      local route_grpc = assert(bp.routes:insert {
        protocols = { "grpc" },
        paths = { "/hello.HelloService/" },
        service = assert(bp.services:insert {
          name = "grpc",
          url = helpers.grpcbin_url,
        }),
      })

      bp.plugins:insert {
        name     = "hmac-auth",
        route = { id = route1.id },
        config   = {
          clock_skew = 3000,
          realm = "test-realm"
        }
      }

      bp.plugins:insert {
        name     = "hmac-auth",
        route = { id = route_grpc.id },
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
        hosts = { "hmacauth2.test" },
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
        hosts = { "hmacauth3.test" },
      }

      bp.plugins:insert {
        name     = "hmac-auth",
        route = { id = route3.id },
        config   = {
          anonymous  = uuid.uuid(),  -- non existing consumer
          clock_skew = 3000
        }
      }

      local route4 = bp.routes:insert {
        hosts = { "hmacauth4.test" },
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
        hosts = { "hmacauth5.test" },
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
        hosts = { "hmacauth6.test" },
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
        hosts = { "hmacauth7.test" },
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
      describe("when realm is set", function ()
        it("should not be authorized when the hmac credentials are missing", function()
          local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
          local res = assert(proxy_client:send {
            method = "POST",
            body = {},
            headers = {
              ["HOST"] = "hmacauth.test",
              date = date
            }
          })
          local body = assert.res_status(401, res)
          assert.equal('hmac realm="test-realm"', res.headers["WWW-Authenticate"])
          body = cjson.decode(body)
          assert.equal("Unauthorized", body.message)
        end)
      end)

      describe("when realm is not set", function ()
        it("should return a 401 with an invalid authorization header", function()
          local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/request",
            body    = {},
            headers = {
              ["HOST"]                = "hmacauth6.test",
              date                    = date,
              ["proxy-authorization"] = "this is no hmac token at all is it?",
            },
          })
          assert.res_status(401, res)
          assert.equal('hmac', res.headers["WWW-Authenticate"])
        end)
      end)

      it("rejects gRPC call without credentials", function()
        local ok, err = helpers.proxy_client_grpc(){
          service = "hello.HelloService.SayHello",
          opts = {},
        }
        assert.falsy(ok)
        assert.matches("Code: Unauthenticated", err)
      end)

      it("should not be authorized when the HMAC signature is wrong", function()
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
        local res = assert(proxy_client:send {
          method = "POST",
          body = {},
          headers = {
            ["HOST"] = "hmacauth.test",
            date = date,
            authorization = "asd"
          }
        })
        local body = assert.res_status(401, res)
        assert.equal('hmac realm="test-realm"', res.headers["WWW-Authenticate"])
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
            ["HOST"]      = "hmacauth.test",
            date          = date,
            authorization = hmacAuth
          }
        })
        local body = assert.res_status(401, res)
        assert.equal('hmac realm="test-realm"', res.headers["WWW-Authenticate"])
        body = cjson.decode(body)
        assert.equal("HMAC signature does not match", body.message)
      end)

      it("should not be authorized when date header is missing", function()
        local res = assert(proxy_client:send {
          method = "POST",
          body = {},
          headers = {
            ["HOST"] = "hmacauth.test",
            authorization = "asd"
          }
        })
        local body = assert.res_status(401, res)
        assert.equal('hmac realm="test-realm"', res.headers["WWW-Authenticate"])
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
            ["HOST"] = "hmacauth.test",
            date = date,
            ["proxy-authorization"] = "asd"
          }
        })
        local body = assert.res_status(401, res)
        assert.equal('hmac realm="test-realm"', res.headers["WWW-Authenticate"])
        body = cjson.decode(body)
        assert.equal(SIGNATURE_NOT_VALID, body.message)
      end)

      it("should not pass when passing only the digest", function()
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
        local res = assert(proxy_client:send {
          method = "POST",
          body = {},
          headers = {
            ["HOST"] = "hmacauth.test",
            date = date,
            ["proxy-authorization"] = "hmac :dXNlcm5hbWU6cGFzc3dvcmQ="
          }
        })
        local body = assert.res_status(401, res)
        assert.equal('hmac realm="test-realm"', res.headers["WWW-Authenticate"])
        body = cjson.decode(body)
        assert.equal(SIGNATURE_NOT_VALID, body.message)
      end)

      it("should not pass when passing wrong hmac parameters", function()
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
        local res = assert(proxy_client:send {
          method = "POST",
          body = {},
          headers = {
            ["HOST"] = "hmacauth.test",
            date = date,
            ["proxy-authorization"] = [[hmac username=,algorithm,]]
              .. [[headers,dXNlcm5hbWU6cGFzc3dvcmQ=]]
          }
        })
        local body = assert.res_status(401, res)
        assert.equal('hmac realm="test-realm"', res.headers["WWW-Authenticate"])
        body = cjson.decode(body)
        assert.equal(SIGNATURE_NOT_VALID, body.message)
      end)

      it("should not pass when passing wrong hmac parameters", function()
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
        local res = assert(proxy_client:send {
          method = "POST",
          body = {},
          headers = {
            ["HOST"] = "hmacauth.test",
            date = date,
            authorization = [[hmac username=,algorithm,]]
              .. [[headers,dXNlcm5hbWU6cGFzc3dvcmQ=]]
          }
        })
        local body = assert.res_status(401, res)
        assert.equal('hmac realm="test-realm"', res.headers["WWW-Authenticate"])
        body = cjson.decode(body)
        assert.equal(SIGNATURE_NOT_VALID, body.message)
      end)

      it("should not be authorized when passing only the username", function()
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
        local res = assert(proxy_client:send {
          method = "POST",
          body = {},
          headers = {
            ["HOST"] = "hmacauth.test",
            date = date,
            authorization = "hmac username"
          }
        })
        local body = assert.res_status(401, res)
        assert.equal('hmac realm="test-realm"', res.headers["WWW-Authenticate"])
        body = cjson.decode(body)
        assert.equal(SIGNATURE_NOT_VALID, body.message)
      end)

      it("should not be authorized when authorization header is missing", function()
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
        local res = assert(proxy_client:send {
          method = "POST",
          body = {},
          headers = {
            ["HOST"] = "hmacauth.test",
            date = date,
          }
        })
        local body = assert.res_status(401, res)
        assert.equal('hmac realm="test-realm"', res.headers["WWW-Authenticate"])
        body = cjson.decode(body)
        assert.equal("Unauthorized", body.message)
      end)

      it("should not pass with username missing", function()
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
        local encodedSignature   = ngx.encode_base64(hmac_sha1_binary("secret", "date: " .. date))
        local hmacAuth = [[hmac algorithm="hmac-sha1",]]
          .. [[headers="date",signature="]] .. encodedSignature .. [["]]
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          body    = {},
          headers = {
            ["HOST"]      = "hmacauth.test",
            date          = date,
            authorization = hmacAuth,
          },
        })
        local body = assert.res_status(401, res)
        assert.equal('hmac realm="test-realm"', res.headers["WWW-Authenticate"])
        body = cjson.decode(body)
        assert.not_nil(body.message)
        assert.matches("HMAC signature cannot be verified", body.message)
      end)

      it("should not pass with signature missing", function()
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
        local hmacAuth = [[hmac username="bob",algorithm="hmac-sha1",]]
          .. [[headers="date"]]
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          body    = {},
          headers = {
            ["HOST"]      = "hmacauth.test",
            date          = date,
            authorization = hmacAuth,
          },
        })
        local body = assert.res_status(401, res)
        assert.equal('hmac realm="test-realm"', res.headers["WWW-Authenticate"])
        body = cjson.decode(body)
        assert.not_nil(body.message)
        assert.matches("HMAC signature cannot be verified", body.message)
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
            ["HOST"]      = "hmacauth.test",
            date          = date,
            authorization = hmacAuth,
          },
        })
        local body = assert.res_status(200, res)
        body = cjson.decode(body)
        assert.equal(hmacAuth, body.headers["authorization"])
      end)

      it("accepts authorized gRPC calls", function()
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
        local encodedSignature   = ngx.encode_base64(hmac_sha1_binary("secret", "date: " .. date))
        local hmacAuth = [[hmac username="bob",algorithm="hmac-sha1",]]
          .. [[headers="date",signature="]] .. encodedSignature .. [["]]

        local ok, res = helpers.proxy_client_grpc(){
          service = "hello.HelloService.SayHello",
          opts = {
            [""] = ("-H 'Date: %s' -H 'Authorization: %s'"):format(date, hmacAuth),
          },
        }
        assert.truthy(ok)
        assert.same({ reply = "hello noname" }, cjson.decode(res))
      end)

      it("accepts authorized gRPC calls with @request-target (HTTP/2 test), bug #3789", function()
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
        local encodedSignature   = ngx.encode_base64(hmac_sha1_binary("secret", "date: " .. date ..
                                                                      "\n@request-target: " ..
                                                                      "post /hello.HelloService/SayHello"))
        local hmacAuth = [[hmac username="bob",algorithm="hmac-sha1",]]
          .. [[headers="date @request-target",signature="]] .. encodedSignature .. [["]]

        local ok, res = helpers.proxy_client_grpc(){
          service = "hello.HelloService.SayHello",
          opts = {
            [""] = ("-H 'Date: %s' -H 'Authorization: %s'"):format(date, hmacAuth),
          },
        }
        assert.truthy(ok)
        assert.same({ reply = "hello noname" }, cjson.decode(res))
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
            ["HOST"]                = "hmacauth.test",
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
            ["HOST"]      = "hmacauth.test",
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
            ["HOST"]                = "hmacauth.test",
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
            ["HOST"]                = "hmacauth.test",
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
            ["HOST"]                = "hmacauth.test",
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
            ["HOST"]                = "hmacauth.test",
            date                    = date,
            ["proxy-authorization"] = hmacAuth,
            authorization           = "hello",
            ["content-md5"]         = "md5",
          },
        })
        assert.res_status(200, res)
      end)

      it("should pass with GET with @request-target", function()
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
        local encodedSignature = ngx.encode_base64(
          hmac_sha1_binary("secret", "date: "
            .. date .. "\n" .. "content-md5: md5" .. "\n@request-target: get /request"))
        local hmacAuth = [[hmac username="bob",  algorithm="hmac-sha1", ]]
          .. [[headers="date content-md5 @request-target", signature="]]
          .. encodedSignature .. [["]]
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          body    = {},
          headers = {
            ["HOST"]                = "hmacauth.test",
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
            ["HOST"]                = "hmacauth.test",
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
                ["HOST"]                = "hmacauth.test",
                date                    = date,
                ["proxy-authorization"] = hmacAuth,
                authorization           = "hello",
                ["content-md5"]         = "md5",
              },
            })

        local body = assert.res_status(401, res)
        assert.equal('hmac realm="test-realm"', res.headers["WWW-Authenticate"])
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
            ["HOST"]                = "hmacauth.test",
            date                    = date,
            ["proxy-authorization"] = hmacAuth,
            authorization           = "hello",
            ["content-md5"]         = "md5",
          },
        })

        local body = assert.res_status(401, res)
        assert.equal('hmac realm="test-realm"', res.headers["WWW-Authenticate"])
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
            ["HOST"]                = "hmacauth.test",
            date                    = date,
            ["proxy-authorization"] = hmacAuth,
            authorization           = "hello",
            ["content-md5"]         = "md5",
          },
        })

        local body = assert.res_status(401, res)
        assert.equal('hmac realm="test-realm"', res.headers["WWW-Authenticate"])
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
            ["HOST"]                = "hmacauth.test",
            date                    = date,
            ["proxy-authorization"] = hmacAuth,
            authorization           = "hello",
            ["content-md5"]         = "md5",
          },
        })
        local body = assert.res_status(401, res)
        assert.equal('hmac realm="test-realm"', res.headers["WWW-Authenticate"])
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
            ["HOST"]                = "hmacauth.test",
            date                    = date,
            ["proxy-authorization"] = hmacAuth,
            authorization           = "hello",
            ["content-md5"]         = "md5",
          },
        })
        local body = assert.res_status(401, res)
        assert.equal('hmac realm="test-realm"', res.headers["WWW-Authenticate"])
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
            ["HOST"]                = "hmacauth.test",
            date                    = date,
            ["proxy-authorization"] = hmacAuth,
            authorization           = "hello",
            ["content-md5"]         = "md5",
          },
        })
        local body = assert.res_status(401, res)
        assert.equal('hmac realm="test-realm"', res.headers["WWW-Authenticate"])
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
            ["HOST"]                = "hmacauth.test",
            date                    = date,
            ["proxy-authorization"] = hmacAuth,
            authorization           = "hello",
            ["content-md5"]         = "md5",
          },
        })
        local body = assert.res_status(401, res)
        assert.equal('hmac realm="test-realm"', res.headers["WWW-Authenticate"])
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
            ["HOST"]                = "hmacauth.test",
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
          openssl_mac.new("secret", "HMAC", nil, "sha256"):final("date: " .. date .. "\n"
            .. "content-md5: md5" .. "\nGET /request HTTP/1.1"))
        local hmacAuth = [[hmac username="bob",algorithm="hmac-sha",]]
          .. [[  headers="date content-md5 request-line",signature="]]
          .. encodedSignature .. [["]]
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          body    = {},
          headers = {
            ["HOST"]                = "hmacauth.test",
            date                    = date,
            ["proxy-authorization"] = hmacAuth,
            authorization           = "hello",
            ["content-md5"]         = "md5",
          },
        })
        assert.res_status(401, res)
        assert.equal('hmac realm="test-realm"', res.headers["WWW-Authenticate"])
      end)

      it("should pass the right headers to the upstream server", function()
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
        local encodedSignature = ngx.encode_base64(
          openssl_mac.new("secret", "HMAC", nil, "sha256"):final("date: " .. date .. "\n"
                             .. "content-md5: md5" .. "\nGET /request HTTP/1.1"))
        local hmacAuth = [[hmac username="bob",algorithm="hmac-sha256",]]
          .. [[  headers="date content-md5 request-line",signature="]]
          .. encodedSignature .. [["]]
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          body    = {},
          headers = {
            ["HOST"]                = "hmacauth.test",
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
        assert.equal(credential.username, parsed_body.headers["x-credential-identifier"])
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
            ["HOST"]        = "hmacauth.test",
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
            ["HOST"]                = "hmacauth.test",
            ["proxy-authorization"] = hmacAuth,
            authorization           = "hello",
            ["content-md5"]         = "md5",
          },
        })
        local body = assert.res_status(401, res)
        assert.equal('hmac realm="test-realm"', res.headers["WWW-Authenticate"])
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
            ["HOST"]        = "hmacauth.test",
            ["x-date"]      = "wrong date",
            authorization   = hmacAuth,
            ["content-md5"] = "md5",
          },
        })
        local body = assert.res_status(401, res)
        assert.equal('hmac realm="test-realm"', res.headers["WWW-Authenticate"])
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
            ["HOST"]        = "hmacauth.test",
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
            ["HOST"]        = "hmacauth.test",
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
            ["HOST"]        = "hmacauth.test",
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
            ["HOST"]        = "hmacauth.test",
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
            ["HOST"]      = "hmacauth2.test",
            date          = date,
            authorization = hmacAuth,
          },
        })
        local body = assert.res_status(200, res)
        body = cjson.decode(body)
        assert.equal(hmacAuth, body.headers["authorization"])
        assert.equal("bob", body.headers["x-consumer-username"])
        assert.equal(credential.username, body.headers["x-credential-identifier"])
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
            ["HOST"]      = "hmacauth4.test",
            date          = date,
            authorization = hmacAuth,
          }
        })
        local body = assert.res_status(401, res)
        assert.equal('hmac', res.headers["WWW-Authenticate"])
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
            ["HOST"]      = "hmacauth4.test",
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
            ["HOST"]      = "hmacauth4.test",
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
            ["HOST"] = "hmacauth2.test",
          },
        })
        local body = assert.res_status(200, res)
        body = cjson.decode(body)
        assert.equal("true", body.headers["x-anonymous-consumer"])
        assert.equal('no-body', body.headers["x-consumer-username"])
        assert.equal(nil, body.headers["x-credential-identifier"])
      end)

      it("should pass with invalid credentials and username in anonymous", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          body    = {},
          headers = {
            ["HOST"] = "hmacauth7.test",
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
            ["Host"] = "hmacauth3.test",
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
            ["HOST"]      = "hmacauth4.test",
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
            ["HOST"]      = "hmacauth4.test",
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
            ["HOST"]      = "hmacauth4.test",
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
            ["HOST"]      = "hmacauth4.test",
            date          = date,
            authorization = hmacAuth,
          },
        })
        local body = assert.res_status(401, res)
        assert.equal('hmac', res.headers["WWW-Authenticate"])
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
            ["HOST"]      = "hmacauth4.test",
            date          = date,
            digest        = digest,
            authorization = hmacAuth,
          },
        })
        local body = assert.res_status(401, res)
        assert.equal('hmac', res.headers["WWW-Authenticate"])
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
            ["HOST"]      = "hmacauth4.test",
            date          = date,
            digest        = digest .. "spoofed",
            authorization = hmacAuth,
          }
        })
        local body = assert.res_status(401, res)
        assert.equal('hmac', res.headers["WWW-Authenticate"])
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
            ["HOST"]                = "hmacauth5.test",
            date                    = date,
            ["proxy-authorization"] = hmacAuth,
            ["content-md5"]         = "md5",
          },
        })
        assert.res_status(200, res)
      end)

      it("should fail with GET with request-line having query param but signed without query param", function()
        -- hmac-auth signature must include the same query param in request-line: https://github.com/Kong/kong/pull/3339
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
            ["HOST"]                = "hmacauth5.test",
            date                    = date,
            ["proxy-authorization"] = hmacAuth,
            ["content-md5"]         = "md5",
          },
        })
        assert.res_status(401, res)
        assert.equal('hmac', res.headers["WWW-Authenticate"])

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
            ["HOST"]                = "hmacauth5.test",
            date                    = date,
            ["proxy-authorization"] = hmacAuth,
            ["content-md5"]         = "md5",
          },
        })
        assert.res_status(401, res)
        assert.equal('hmac', res.headers["WWW-Authenticate"])
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
            ["HOST"]                = "hmacauth5.test",
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
            ["HOST"]                = "hmacauth5.test",
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
            ["HOST"]                = "hmacauth5.test",
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
            ["HOST"]                = "hmacauth5.test",
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
            ["HOST"]                = "hmacauth5.test",
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
            ["HOST"]                = "hmacauth5.test",
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
            ["HOST"]                = "hmacauth5.test",
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
            ["HOST"]                = "hmacauth5.test",
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
            ["HOST"]                = "hmacauth5.test",
            date                    = date,
            ["proxy-authorization"] = hmacAuth,
            ["content-md5"]         = "md5",
          },
        })
        assert.res_status(401, res)
        assert.equal('hmac', res.headers["WWW-Authenticate"])
      end)

      it("should pass with GET with hmac-sha384", function()
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
        local encodedSignature = ngx.encode_base64(
          openssl_mac.new("secret", "HMAC", nil, "sha384"):final("date: " .. date .. "\n"
                  .. "content-md5: md5" .. "\nGET /request HTTP/1.1"))
        local hmacAuth = [[hmac username="bob",  algorithm="hmac-sha384", ]]
                .. [[headers="date content-md5 request-line", signature="]]
                .. encodedSignature .. [["]]
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          body    = {},
          headers = {
            ["HOST"]                = "hmacauth5.test",
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
          openssl_mac.new("secret", "HMAC", nil, "sha512"):final("date: " .. date .. "\n"
                  .. "content-md5: md5" .. "\nGET /request HTTP/1.1"))
        local hmacAuth = [[hmac username="bob",  algorithm="hmac-sha512", ]]
                .. [[headers="date content-md5 request-line", signature="]]
                .. encodedSignature .. [["]]
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          body    = {},
          headers = {
            ["HOST"]                = "hmacauth5.test",
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
          openssl_mac.new("secret", "HMAC", nil, "sha512"):final("date: " .. date .. "\n"
                  .. "content-md5: md5" .. "\nGET /request HTTP/1.1"))
        local hmacAuth = [[hmac username="bob",  algorithm="hmac-sha512", ]]
                .. [[headers="date content-md5 request-line", signature="]]
                .. encodedSignature .. [["]]
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          body    = {},
          headers = {
            ["HOST"]                = "hmacauth6.test",
            date                    = date,
            ["proxy-authorization"] = hmacAuth,
            ["content-md5"]         = "md5",
          },
        })
        assert.res_status(401, res)
        assert.equal('hmac', res.headers["WWW-Authenticate"])
      end)

      it("should return a 401 with an invalid authorization header", function()
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          body    = {},
          headers = {
            ["HOST"]                = "hmacauth6.test",
            date                    = date,
            ["proxy-authorization"] = "this is no hmac token at all is it?",
          },
        })
        assert.res_status(401, res)
        assert.equal('hmac', res.headers["WWW-Authenticate"])
      end)

      it("should pass with hmac-sha1", function()
        local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
        local encodedSignature = ngx.encode_base64(
          openssl_mac.new("secret", "HMAC", nil, "sha1"):final("date: " .. date .. "\n"
                  .. "content-md5: md5" .. "\nGET /request HTTP/1.1"))
        local hmacAuth = [[hmac username="bob",  algorithm="hmac-sha1", ]]
                .. [[headers="date content-md5 request-line", signature="]]
                .. encodedSignature .. [["]]
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          body    = {},
          headers = {
            ["HOST"]                = "hmacauth6.test",
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
        hosts      = { "logical-and.test" },
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
        hosts      = { "logical-or.test" },
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
            ["Host"]          = "logical-and.test",
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
            ["Host"]   = "logical-and.test",
            ["apikey"] = "Mouse",
          },
        })
        assert.response(res).has.status(401)
        assert.equal('hmac', res.headers["WWW-Authenticate"])
      end)

      it("fails 401, with only the second credential provided", function()
        local res = assert(proxy_client:send {
          method = "GET",
          path   = "/request",
          headers = {
            ["Host"]          = "logical-and.test",
            ["Authorization"] = hmacAuth,
            ["date"]          = hmacDate,
          },
        })
        assert.response(res).has.status(401)
        assert.equal('Key', res.headers["WWW-Authenticate"])
      end)

      it("fails 401, with no credential provided", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Host"] = "logical-and.test",
          },
        })
        assert.response(res).has.status(401)
        assert.equal('Key', res.headers["WWW-Authenticate"])
      end)

    end)

    describe("multiple auth with anonymous, logical OR", function()

      it("passes with all credentials provided", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Host"]          = "logical-or.test",
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
            ["Host"]   = "logical-or.test",
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
            ["Host"]          = "logical-or.test",
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
            ["Host"] = "logical-or.test",
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
