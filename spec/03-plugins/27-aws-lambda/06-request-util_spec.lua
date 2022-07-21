local helpers = require "spec.helpers"
local fixtures = require "spec.fixtures.aws-lambda"


for _, strategy in helpers.each_strategy() do
  describe("[AWS Lambda] request-util [#" .. strategy .. "]", function()
    local proxy_client
    local admin_client

    lazy_setup(function()
      local bp, db = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
      }, { "aws-lambda" })


      local route1 = bp.routes:insert {
        hosts = { "gw.skipfile.com" },
      }
      bp.plugins:insert {
        name     = "aws-lambda",
        route    = { id = route1.id },
        config   = {
          port                  = 10001,
          aws_key               = "mock-key",
          aws_secret            = "mock-secret",
          aws_region            = "us-east-1",
          function_name         = "kongLambdaTest",
          awsgateway_compatible = true,
          forward_request_body  = true,
          skip_large_bodies     = true,
        },
      }

      local route2 = bp.routes:insert {
        hosts = { "gw.readfile.com" },
      }
      bp.plugins:insert {
        name     = "aws-lambda",
        route    = { id = route2.id },
        config   = {
          port                  = 10001,
          aws_key               = "mock-key",
          aws_secret            = "mock-secret",
          aws_region            = "us-east-1",
          function_name         = "kongLambdaTest",
          awsgateway_compatible = true,
          forward_request_body  = true,
          skip_large_bodies     = false,
        },
      }

      local route3 = bp.routes:insert {
        hosts = { "plain.skipfile.com" },
      }
      bp.plugins:insert {
        name     = "aws-lambda",
        route    = { id = route3.id },
        config   = {
          port                  = 10001,
          aws_key               = "mock-key",
          aws_secret            = "mock-secret",
          aws_region            = "us-east-1",
          function_name         = "kongLambdaTest",
          awsgateway_compatible = false,
          forward_request_body  = true,
          skip_large_bodies     = true,
        },
      }

      local route4 = bp.routes:insert {
        hosts = { "plain.readfile.com" },
      }
      bp.plugins:insert {
        name     = "aws-lambda",
        route    = { id = route4.id },
        config   = {
          port                  = 10001,
          aws_key               = "mock-key",
          aws_secret            = "mock-secret",
          aws_region            = "us-east-1",
          function_name         = "kongLambdaTest",
          awsgateway_compatible = false,
          forward_request_body  = true,
          skip_large_bodies     = false,
        },
      }

      local route5 = bp.routes:insert {
        hosts = { "base.sixtyfour.test" },
      }
      bp.plugins:insert {
        name     = "aws-lambda",
        route    = { id = route5.id },
        config   = {
          port                  = 10001,
          aws_key               = "mock-key",
          aws_secret            = "mock-secret",
          aws_region            = "us-east-1",
          function_name         = "kongLambdaTest",
          awsgateway_compatible = false,
          forward_request_body  = true,
          skip_large_bodies     = false,
          --base64_encode_body    = true,
        },
      }

      local route6 = bp.routes:insert {
        hosts = { "notbase.sixtyfour.test" },
      }
      bp.plugins:insert {
        name     = "aws-lambda",
        route    = { id = route6.id },
        config   = {
          port                  = 10001,
          aws_key               = "mock-key",
          aws_secret            = "mock-secret",
          aws_region            = "us-east-1",
          function_name         = "kongLambdaTest",
          awsgateway_compatible = false,
          forward_request_body  = true,
          skip_large_bodies     = false,
          base64_encode_body    = false,
        },
      }

      local route7 = db.routes:insert {
        hosts = { "gw.serviceless.com" },
      }
      db.plugins:insert {
        name     = "aws-lambda",
        route    = { id = route7.id },
        config   = {
          port                  = 10001,
          aws_key               = "mock-key",
          aws_secret            = "mock-secret",
          aws_region            = "us-east-1",
          function_name         = "kongLambdaTest",
          awsgateway_compatible = true,
          forward_request_body  = true,
          skip_large_bodies     = true,
        },
      }


      assert(helpers.start_kong({
        database   = strategy,
        plugins = "aws-lambda",
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }, nil, nil, fixtures))
    end)

    before_each(function()
      proxy_client = helpers.proxy_client()
      admin_client = helpers.admin_client()
      os.execute(":> " .. helpers.test_conf.nginx_err_logs) -- clean log files
    end)

    after_each(function ()
      proxy_client:close()
      admin_client:close()
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)


    describe("plain:", function() -- plain serialization, not AWS gateway compatible

      describe("when skip_large_bodies is true", function()

        it("it skips file-buffered body > max buffer size", function()
          local request_body = ("a"):rep(32 * 1024)  -- 32 kb
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/get?key1=some_value1&key2=some_value2&key3=some_value3",
            headers = {
              ["Host"] = "plain.skipfile.com"
            },
            body = request_body
          })
          assert.response(res).has.status(200, res)
          local body = assert.response(res).has.jsonbody()
          assert.is_string(res.headers["x-amzn-RequestId"])
          assert.equal("", body.request_body) -- empty because it was skipped
          assert.logfile().has.line("request body was buffered to disk, too large", true)
        end)


        it("it reads body < max buffer size", function()
          local request_body = ("a"):rep(1 * 1024)  -- 1 kb
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/get?key1=some_value1&key2=some_value2&key3=some_value3",
            headers = {
              ["Host"] = "plain.skipfile.com"
            },
            body = request_body,
          })
          assert.response(res).has.status(200, res)
          local body = assert.response(res).has.jsonbody()
          assert.is_string(res.headers["x-amzn-RequestId"])
          assert.equal(ngx.encode_base64(request_body), body.request_body) -- matches because it was small enough
          assert.logfile().has.no.line("request body was buffered to disk, too large", true)
        end)

      end)



      describe("when skip_large_bodies is false", function()

        it("it reads file-buffered body > max buffer size", function()
          local request_body = ("a"):rep(32 * 1024)  -- 32 kb
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/get?key1=some_value1&key2=some_value2&key3=some_value3",
            headers = {
              ["Host"] = "plain.readfile.com"
            },
            body = request_body
          })
          assert.response(res).has.status(200, res)
          local body = assert.response(res).has.jsonbody()
          assert.is_string(res.headers["x-amzn-RequestId"])
          assert.equal(ngx.encode_base64(request_body), body.request_body) -- matches because it was read from file
          assert.logfile().has.no.line("request body was buffered to disk, too large", true)
        end)


        it("it reads body < max buffer size", function()
          local request_body = ("a"):rep(1 * 1024)  -- 1 kb
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/get?key1=some_value1&key2=some_value2&key3=some_value3",
            headers = {
              ["Host"] = "plain.readfile.com"
            },
            body = request_body,
          })
          assert.response(res).has.status(200, res)
          local body = assert.response(res).has.jsonbody()
          assert.is_string(res.headers["x-amzn-RequestId"])
          assert.equal(ngx.encode_base64(request_body), body.request_body) -- matches because it was small enough
          assert.logfile().has.no.line("request body was buffered to disk, too large", true)
        end)

      end)
    end)



    describe("aws-gw:", function() -- AWS gateway compatible serialization

      describe("when skip_large_bodies is true", function()

        it("it skips file-buffered body > max buffer size", function()
          local request_body = ("a"):rep(32 * 1024)  -- 32 kb
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/get?key1=some_value1&key2=some_value2&key3=some_value3",
            headers = {
              ["Host"] = "gw.skipfile.com"
            },
            body = request_body
          })
          assert.response(res).has.status(200, res)
          local body = assert.response(res).has.jsonbody()
          assert.is_string(res.headers["x-amzn-RequestId"])
          assert.equal("", body.body) -- empty because it was skipped
          assert.logfile().has.line("request body was buffered to disk, too large", true)
        end)


        it("it reads body < max buffer size", function()
          local request_body = ("a"):rep(1 * 1024)  -- 1 kb
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/get?key1=some_value1&key2=some_value2&key3=some_value3",
            headers = {
              ["Host"] = "gw.skipfile.com"
            },
            body = request_body,
          })
          assert.response(res).has.status(200, res)
          local body = assert.response(res).has.jsonbody()
          assert.is_string(res.headers["x-amzn-RequestId"])
          assert.equal(ngx.encode_base64(request_body), body.body) -- matches because it was small enough
          assert.logfile().has.no.line("request body was buffered to disk, too large", true)
        end)

      end)



      describe("when skip_large_bodies is false", function()

        it("it reads file-buffered body > max buffer size", function()
          local request_body = ("a"):rep(32 * 1024)  -- 32 kb
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/get?key1=some_value1&key2=some_value2&key3=some_value3",
            headers = {
              ["Host"] = "gw.readfile.com"
            },
            body = request_body
          })
          assert.response(res).has.status(200, res)
          local body = assert.response(res).has.jsonbody()
          assert.is_string(res.headers["x-amzn-RequestId"])
          assert.equal(ngx.encode_base64(request_body), body.body) -- matches because it was read from file
          assert.logfile().has.no.line("request body was buffered to disk, too large", true)
        end)


        it("it reads body < max buffer size", function()
          local request_body = ("a"):rep(1 * 1024)  -- 1 kb
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/get?key1=some_value1&key2=some_value2&key3=some_value3",
            headers = {
              ["Host"] = "gw.readfile.com"
            },
            body = request_body,
          })
          assert.response(res).has.status(200, res)
          local body = assert.response(res).has.jsonbody()
          assert.is_string(res.headers["x-amzn-RequestId"])
          assert.equal(ngx.encode_base64(request_body), body.body) -- matches because it was small enough
          assert.logfile().has.no.line("request body was buffered to disk, too large", true)
        end)

      end)
    end)



    describe("base64 body encoding", function()

      it("enabled", function()
        local request_body = ("encodemeplease")
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get?key1=some_value1&key2=some_value2&key3=some_value3",
          headers = {
            ["Host"] = "base.sixtyfour.test"
          },
          body = request_body,
        })
        assert.response(res).has.status(200, res)
        local body = assert.response(res).has.jsonbody()
        assert.equal(ngx.encode_base64(request_body), body.request_body)
      end)


      it("disabled", function()
        local request_body = ("donotencodemeplease")
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get?key1=some_value1&key2=some_value2&key3=some_value3",
          headers = {
            ["Host"] = "notbase.sixtyfour.test"
          },
          body = request_body,
        })
        assert.response(res).has.status(200, res)
        local body = assert.response(res).has.jsonbody()
        assert.equal(request_body, body.request_body)
      end)

    end)

    describe("serviceless plugin", function()

      it("serviceless", function()
        local request_body = ("encodemeplease")
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get?key1=some_value1&key2=some_value2&key3=some_value3",
          headers = {
            ["Host"] = "gw.serviceless.com"
          },
          body = request_body,
        })
        assert.response(res).has.status(200, res)
        assert.is_string(res.headers["x-amzn-RequestId"])
      end)
    end)

  end)
end
