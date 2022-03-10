local cjson   = require "cjson"
local helpers = require "spec.helpers"
local meta    = require "kong.meta"
local pl_file = require "pl.file"
local fixtures = require "spec.fixtures.aws-lambda"

local TEST_CONF = helpers.test_conf
local server_tokens = meta._SERVER_TOKENS
local null = ngx.null



for _, strategy in helpers.each_strategy() do
  describe("Plugin: AWS Lambda (access) [#" .. strategy .. "]", function()
    local proxy_client
    local admin_client

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
      }, { "aws-lambda" })

      local route1 = bp.routes:insert {
        hosts = { "lambda.com" },
      }

      local route1_1 = bp.routes:insert {
        hosts = { "lambda_ignore_service.com" },
        service    = bp.services:insert({
          protocol = "http",
          host     = "httpbin.org",
          port     = 80,
        })
      }

      local route2 = bp.routes:insert {
        hosts = { "lambda2.com" },
      }

      local route3 = bp.routes:insert {
        hosts = { "lambda3.com" },
      }

      local route4 = bp.routes:insert {
        hosts = { "lambda4.com" },
      }

      local route5 = bp.routes:insert {
        hosts = { "lambda5.com" },
      }

      local route6 = bp.routes:insert {
        hosts = { "lambda6.com" },
      }

      local route7 = bp.routes:insert {
        hosts = { "lambda7.com" },
      }

      local route8 = bp.routes:insert {
        hosts = { "lambda8.com" },
      }

      local route9 = bp.routes:insert {
        hosts      = { "lambda9.com" },
        protocols  = { "http", "https" },
        service    = null,
      }

      local route10 = bp.routes:insert {
        hosts       = { "lambda10.com" },
        protocols   = { "http", "https" },
        service     = null,
      }

      local route11 = bp.routes:insert {
        hosts       = { "lambda11.com" },
        protocols   = { "http", "https" },
        service     = null,
      }

      local route12 = bp.routes:insert {
        hosts       = { "lambda12.com" },
        protocols   = { "http", "https" },
        service     = null,
      }

      local route13 = bp.routes:insert {
        hosts       = { "lambda13.com" },
        protocols   = { "http", "https" },
        service     = null,
      }

      local route14 = bp.routes:insert {
        hosts       = { "lambda14.com" },
        protocols   = { "http", "https" },
        service     = null,
      }

      local route15 = bp.routes:insert {
        hosts       = { "lambda15.com" },
        protocols   = { "http", "https" },
        service     = null,
      }

      local route16 = bp.routes:insert {
        hosts       = { "lambda16.com" },
        protocols   = { "http", "https" },
        service     = null,
      }

      local route17 = bp.routes:insert {
        hosts       = { "lambda17.com" },
        protocols   = { "http", "https" },
        service     = null,
      }

      local route18 = bp.routes:insert {
        hosts       = { "lambda18.com" },
        protocols   = { "http", "https" },
        service     = null,
      }

      local route19 = bp.routes:insert {
        hosts       = { "lambda19.com" },
        protocols   = { "http", "https" },
        service     = null,
      }

      local route20 = bp.routes:insert {
        hosts       = { "lambda20.com" },
        protocols   = { "http", "https" },
        service     = null,
      }

      local route21 = bp.routes:insert {
        hosts       = { "lambda21.com" },
        protocols   = { "http", "https" },
        service     = null,
      }


      bp.plugins:insert {
        name     = "aws-lambda",
        route    = { id = route1.id },
        config   = {
          port          = 10001,
          aws_key       = "mock-key",
          aws_secret    = "mock-secret",
          aws_region    = "us-east-1",
          function_name = "kongLambdaTest",
        },
      }

      bp.plugins:insert {
        name     = "aws-lambda",
        route    = { id = route1_1.id },
        config   = {
          port          = 10001,
          aws_key       = "mock-key",
          aws_secret    = "mock-secret",
          aws_region    = "us-east-1",
          function_name = "kongLambdaTest",
        },
      }

      bp.plugins:insert {
        name     = "aws-lambda",
        route    = { id = route2.id },
        config   = {
          port            = 10001,
          aws_key         = "mock-key",
          aws_secret      = "mock-secret",
          aws_region      = "us-east-1",
          function_name   = "kongLambdaTest",
          invocation_type = "Event",
        },
      }

      bp.plugins:insert {
        name     = "aws-lambda",
        route    = { id = route3.id },
        config   = {
          port            = 10001,
          aws_key         = "mock-key",
          aws_secret      = "mock-secret",
          aws_region      = "us-east-1",
          function_name   = "kongLambdaTest",
          invocation_type = "DryRun",
        },
      }

      bp.plugins:insert {
        name     = "aws-lambda",
        route    = { id = route4.id },
        config   = {
          port          = 10001,
          aws_key       = "mock-key",
          aws_secret    = "mock-secret",
          aws_region    = "us-east-1",
          function_name = "kongLambdaTest",
          timeout       = 100,
        },
      }

      bp.plugins:insert {
        name     = "aws-lambda",
        route    = { id = route5.id },
        config   = {
          port          = 10001,
          aws_key       = "mock-key",
          aws_secret    = "mock-secret",
          aws_region    = "us-east-1",
          function_name = "functionWithUnhandledError",
        },
      }

      bp.plugins:insert {
        name     = "aws-lambda",
        route    = { id = route6.id },
        config   = {
          port            = 10001,
          aws_key         = "mock-key",
          aws_secret      = "mock-secret",
          aws_region      = "us-east-1",
          function_name   = "functionWithUnhandledError",
          invocation_type = "Event",
        },
      }

      bp.plugins:insert {
        name     = "aws-lambda",
        route    = { id = route7.id },
        config   = {
          port            = 10001,
          aws_key         = "mock-key",
          aws_secret      = "mock-secret",
          aws_region      = "us-east-1",
          function_name   = "functionWithUnhandledError",
          invocation_type = "DryRun",
        },
      }

      bp.plugins:insert {
        name     = "aws-lambda",
        route    = { id = route8.id },
        config   = {
          port             = 10001,
          aws_key          = "mock-key",
          aws_secret       = "mock-secret",
          aws_region       = "us-east-1",
          function_name    = "functionWithUnhandledError",
          unhandled_status = 412,
        },
      }

      bp.plugins:insert {
        name     = "aws-lambda",
        route    = { id = route9.id },
        config   = {
          port                    = 10001,
          aws_key                 = "mock-key",
          aws_secret              = "mock-secret",
          aws_region              = "us-east-1",
          function_name           = "kongLambdaTest",
          forward_request_method  = true,
          forward_request_uri     = true,
          forward_request_headers = true,
          forward_request_body    = true,
        }
      }

      bp.plugins:insert {
        name     = "aws-lambda",
        route    = { id = route10.id },
        config                    = {
          port                    = 10001,
          aws_key                 = "mock-key",
          aws_secret              = "mock-secret",
          aws_region              = "us-east-1",
          function_name           = "kongLambdaTest",
          forward_request_method  = true,
          forward_request_uri     = false,
          forward_request_headers = true,
          forward_request_body    = true,
        }
      }

      bp.plugins:insert {
        name     = "aws-lambda",
        route    = { id = route11.id },
        config                 = {
          port                 = 10001,
          aws_key              = "mock-key",
          aws_secret           = "mock-secret",
          aws_region           = "us-east-1",
          function_name        = "kongLambdaTest",
          is_proxy_integration = true,
        }
      }

      bp.plugins:insert {
        name     = "aws-lambda",
        route    = { id = route12.id },
        config                 = {
          port                 = 10001,
          aws_key              = "mock-key",
          aws_secret           = "mock-secret",
          aws_region           = "us-east-1",
          function_name        = "functionWithBadJSON",
          is_proxy_integration = true,
        }
      }

      bp.plugins:insert {
        name     = "aws-lambda",
        route    = { id = route13.id },
        config                 = {
          port                 = 10001,
          aws_key              = "mock-key",
          aws_secret           = "mock-secret",
          aws_region           = "us-east-1",
          function_name        = "functionWithNoResponse",
          is_proxy_integration = true,
        }
      }

      bp.plugins:insert {
        name     = "aws-lambda",
        route = { id = route14.id },
        config   = {
          port          = 10001,
          aws_key       = "mock-key",
          aws_secret    = "mock-secret",
          aws_region    = "us-east-1",
          function_name = "kongLambdaTest",
        },
      }

      bp.plugins:insert {
        name     = "aws-lambda",
        route = { id = route15.id },
        config   = {
          port          = 10001,
          aws_key       = "mock-key",
          aws_secret    = "mock-secret",
          aws_region    = "ab-cdef-1",
          function_name = "kongLambdaTest",
        },
      }

      bp.plugins:insert {
        name     = "aws-lambda",
        route    = { id = route16.id },
        config                 = {
          port                 = 10001,
          aws_key              = "mock-key",
          aws_secret           = "mock-secret",
          aws_region           = "us-east-1",
          function_name        = "functionWithBase64EncodedResponse",
          is_proxy_integration = true,
        }
      }

      bp.plugins:insert {
        name     = "aws-lambda",
        route    = { id = route17.id },
        config                 = {
          port                 = 10001,
          aws_key              = "mock-key",
          aws_secret           = "mock-secret",
          aws_region           = "us-east-1",
          function_name        = "functionWithMultiValueHeadersResponse",
          is_proxy_integration = true,
        }
      }

      bp.plugins:insert {
        name     = "aws-lambda",
        route    = { id = route18.id },
        config                 = {
          port                 = 10001,
          aws_key              = "mock-key",
          aws_secret           = "mock-secret",
          function_name        = "functionWithMultiValueHeadersResponse",
          host                 = "custom.lambda.endpoint",
          is_proxy_integration = true,
        }
      }

      bp.plugins:insert {
        name     = "aws-lambda",
        route    = { id = route19.id },
        config                 = {
          port                 = 10001,
          aws_key              = "mock-key",
          aws_secret           = "mock-secret",
          function_name        = "functionWithMultiValueHeadersResponse",
          is_proxy_integration = true,
        }
      }

      bp.plugins:insert {
        name     = "aws-lambda",
        route    = { id = route20.id },
        config                 = {
          port                 = 10001,
          aws_key              = "mock-key",
          aws_secret           = "mock-secret",
          aws_region           = "us-east-1",
          function_name        = "kongLambdaTest",
          host                 = "custom.lambda.endpoint",
        }
      }

      bp.plugins:insert {
        name     = "aws-lambda",
        route    = { id = route21.id },
        config                 = {
          port                 = 10001,
          aws_key              = "mock-key",
          aws_secret           = "mock-secret",
          aws_region           = "us-east-1",
          function_name        = "functionEcho",
          proxy_url            = "http://127.0.0.1:13128",
          keepalive            = 1,
        }
      }

      fixtures.dns_mock:A({
        name = "custom.lambda.endpoint",
        address = "127.0.0.1",
      })

    end)

    before_each(function()
      proxy_client = helpers.proxy_client()
      admin_client = helpers.admin_client()
    end)

    after_each(function ()
      proxy_client:close()
      admin_client:close()
    end)

    describe("AWS_REGION environment is not set", function()

      lazy_setup(function()
        assert(helpers.start_kong({
          database   = strategy,
          plugins = "aws-lambda",
          nginx_conf = "spec/fixtures/custom_nginx.template",
          -- we don't actually use any stream proxy features in this test suite,
          -- but this is needed in order to load our forward-proxy stream_mock fixture
          stream_listen = helpers.get_proxy_ip(false) .. ":19000",
        }, nil, nil, fixtures))
      end)

      lazy_teardown(function()
        helpers.stop_kong()
      end)

      it("invokes a Lambda function with GET", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get?key1=some_value1&key2=some_value2&key3=some_value3",
          headers = {
            ["Host"] = "lambda.com"
          }
        })
        assert.res_status(200, res)
        local body = assert.response(res).has.jsonbody()
        assert.is_string(res.headers["x-amzn-RequestId"])
        assert.equal("some_value1", body.key1)
        assert.is_nil(res.headers["X-Amz-Function-Error"])
      end)

      it("invokes a Lambda function with GET, ignores route's service", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get?key1=some_value1&key2=some_value2&key3=some_value3",
          headers = {
            ["Host"] = "lambda_ignore_service.com"
          }
        })
        assert.res_status(200, res)
        local body = assert.response(res).has.jsonbody()
        assert.is_string(res.headers["x-amzn-RequestId"])
        assert.equal("some_value1", body.key1)
        assert.is_nil(res.headers["X-Amz-Function-Error"])
      end)

      it("invokes a Lambda function with POST params", function()
        local res = assert(proxy_client:send {
          method  = "POST",
          path    = "/post",
          headers = {
            ["Host"]         = "lambda.com",
            ["Content-Type"] = "application/x-www-form-urlencoded"
          },
          body = {
            key1 = "some_value_post1",
            key2 = "some_value_post2",
            key3 = "some_value_post3"
          }
        })
        assert.res_status(200, res)
        local body = assert.response(res).has.jsonbody()
        assert.is_string(res.headers["x-amzn-RequestId"])
        assert.equal("some_value_post1", body.key1)
      end)

      it("invokes a Lambda function with POST json body", function()
        local res = assert(proxy_client:send {
          method  = "POST",
          path    = "/post",
          headers = {
            ["Host"]         = "lambda.com",
            ["Content-Type"] = "application/json"
          },
          body = {
            key1 = "some_value_json1",
            key2 = "some_value_json2",
            key3 = "some_value_json3"
          }
        })
        assert.res_status(200, res)
        local body = assert.response(res).has.jsonbody()
        assert.is_string(res.headers["x-amzn-RequestId"])
        assert.equal("some_value_json1", body.key1)
      end)

      it("passes empty json arrays unmodified", function()
        local res = assert(proxy_client:send {
          method  = "POST",
          path    = "/post",
          headers = {
            ["Host"]         = "lambda.com",
            ["Content-Type"] = "application/json"
          },
          body = '[{}, []]'
        })
        assert.res_status(200, res)
        assert.equal('[{},[]]', string.gsub(res:read_body(), "\n",""))
      end)

      it("invokes a Lambda function with POST and both querystring and body params", function()
        local res = assert(proxy_client:send {
          method  = "POST",
          path    = "/post?key1=from_querystring",
          headers = {
            ["Host"]         = "lambda.com",
            ["Content-Type"] = "application/x-www-form-urlencoded"
          },
          body = {
            key2 = "some_value_post2",
            key3 = "some_value_post3"
          }
        })
        assert.res_status(200, res)
        local body = assert.response(res).has.jsonbody()
        assert.is_string(res.headers["x-amzn-RequestId"])
        assert.equal("from_querystring", body.key1)
      end)

      it("invokes a Lambda function with POST and xml payload, custom header and query parameter", function()
        local res = assert(proxy_client:send {
          method  = "POST",
          path    = "/post?key1=from_querystring",
          headers = {
            ["Host"]          = "lambda9.com",
            ["Content-Type"]  = "application/xml",
            ["custom-header"] = "someheader"
          },
          body = "<xml/>"
        })
        assert.res_status(200, res)
        local body = assert.response(res).has.jsonbody()
        assert.is_string(res.headers["x-amzn-RequestId"])

        -- request_method
        assert.equal("POST", body.request_method)

        -- request_uri
        assert.equal("/post?key1=from_querystring", body.request_uri)
        assert.is_table(body.request_uri_args)

        -- request_headers
        assert.equal("someheader", body.request_headers["custom-header"])
        assert.equal("lambda9.com", body.request_headers.host)

        -- request_body
        assert.equal("<xml/>", body.request_body)
        assert.is_table(body.request_body_args)
      end)

      it("invokes a Lambda function with POST and json payload, custom header and query parameter", function()
        local res = assert(proxy_client:send {
          method  = "POST",
          path    = "/post?key1=from_querystring",
          headers = {
            ["Host"]          = "lambda10.com",
            ["Content-Type"]  = "application/json",
            ["custom-header"] = "someheader"
          },
          body = { key2 = "some_value" }
        })
        assert.res_status(200, res)
        local body = assert.response(res).has.jsonbody()
        assert.is_string(res.headers["x-amzn-RequestId"])

        -- request_method
        assert.equal("POST", body.request_method)

        -- no request_uri
        assert.is_nil(body.request_uri)
        assert.is_nil(body.request_uri_args)

        -- request_headers
        assert.equal("lambda10.com", body.request_headers.host)
        assert.equal("someheader", body.request_headers["custom-header"])

        -- request_body
        assert.equal("some_value", body.request_body_args.key2)
        assert.is_table(body.request_body_args)
      end)

      it("invokes a Lambda function with POST and txt payload, custom header and query parameter", function()
        local res = assert(proxy_client:send {
          method  = "POST",
          path    = "/post?key1=from_querystring",
          headers = {
            ["Host"]          = "lambda9.com",
            ["Content-Type"]  = "text/plain",
            ["custom-header"] = "someheader"
          },
          body = "some text"
        })
        assert.res_status(200, res)
        local body = assert.response(res).has.jsonbody()
        assert.is_string(res.headers["x-amzn-RequestId"])

        -- request_method
        assert.equal("POST", body.request_method)

        -- request_uri
        assert.equal("/post?key1=from_querystring", body.request_uri)
        assert.is_table(body.request_uri_args)

        -- request_headers
        assert.equal("someheader", body.request_headers["custom-header"])
        assert.equal("lambda9.com", body.request_headers.host)

        -- request_body
        assert.equal("some text", body.request_body)
        assert.is_nil(body.request_body_base64)
        assert.is_table(body.request_body_args)
      end)

      it("invokes a Lambda function with POST and binary payload and custom header", function()
        local res = assert(proxy_client:send {
          method  = "POST",
          path    = "/post?key1=from_querystring",
          headers = {
            ["Host"]          = "lambda9.com",
            ["Content-Type"]  = "application/octet-stream",
            ["custom-header"] = "someheader"
          },
          body = "01234"
        })
        assert.res_status(200, res)
        local body = assert.response(res).has.jsonbody()
        assert.is_string(res.headers["x-amzn-RequestId"])

        -- request_method
        assert.equal("POST", body.request_method)

        -- request_uri
        assert.equal("/post?key1=from_querystring", body.request_uri)
        assert.is_table(body.request_uri_args)

        -- request_headers
        assert.equal("lambda9.com", body.request_headers.host)
        assert.equal("someheader", body.request_headers["custom-header"])

        -- request_body
        assert.equal(ngx.encode_base64('01234'), body.request_body)
        assert.is_true(body.request_body_base64)
        assert.is_table(body.request_body_args)
      end)

      it("invokes a Lambda function with POST params and Event invocation_type", function()
        local res = assert(proxy_client:send {
          method  = "POST",
          path    = "/post",
          headers = {
            ["Host"]         = "lambda2.com",
            ["Content-Type"] = "application/x-www-form-urlencoded"
          },
          body = {
            key1 = "some_value_post1",
            key2 = "some_value_post2",
            key3 = "some_value_post3"
          }
        })
        assert.res_status(202, res)
        assert.is_string(res.headers["x-amzn-RequestId"])
      end)

      it("invokes a Lambda function with POST params and DryRun invocation_type", function()
        local res = assert(proxy_client:send {
          method  = "POST",
          path    = "/post",
          headers = {
            ["Host"]         = "lambda3.com",
            ["Content-Type"] = "application/x-www-form-urlencoded"
          },
          body = {
            key1 = "some_value_post1",
            key2 = "some_value_post2",
            key3 = "some_value_post3"
          }
        })
        assert.res_status(204, res)
        assert.is_string(res.headers["x-amzn-RequestId"])
      end)

      it("errors on connection timeout", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get?key1=some_value1&key2=some_value2&key3=some_value3",
          headers = {
            ["Host"] = "lambda4.com",
          }
        })
        assert.res_status(500, res)
      end)

      it("invokes a Lambda function with an unhandled function error (and no unhandled_status set)", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get?key1=some_value1&key2=some_value2&key3=some_value3",
          headers = {
            ["Host"] = "lambda5.com"
          }
        })
        assert.res_status(200, res)
        assert.equal("Unhandled", res.headers["X-Amz-Function-Error"])
      end)

      it("invokes a Lambda function with an unhandled function error with Event invocation type", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get?key1=some_value1&key2=some_value2&key3=some_value3",
          headers = {
            ["Host"] = "lambda6.com"
          }
        })
        assert.res_status(202, res)
        assert.equal("Unhandled", res.headers["X-Amz-Function-Error"])
      end)

      it("invokes a Lambda function with an unhandled function error with DryRun invocation type", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get?key1=some_value1&key2=some_value2&key3=some_value3",
          headers = {
            ["Host"] = "lambda7.com"
          }
        })
        assert.res_status(204, res)
        assert.equal("Unhandled", res.headers["X-Amz-Function-Error"])
      end)

      it("invokes a Lambda function with an unhandled function error", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get?key1=some_value1&key2=some_value2&key3=some_value3",
          headers = {
            ["Host"] = "lambda8.com"
          }
        })
        assert.res_status(412, res)
        assert.equal("Unhandled", res.headers["X-Amz-Function-Error"])
      end)

      it("returns server tokens with Via header", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get?key1=some_value1&key2=some_value2&key3=some_value3",
          headers = {
            ["Host"] = "lambda.com"
          }
        })

        if server_tokens then
          assert.equal(server_tokens, res.headers["Via"])
        end
      end)

      it("returns Content-Length header", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get?key1=some_value1&key2=some_value2&key3=some_value3",
          headers = {
            ["Host"] = "lambda.com"
          }
        })

        assert.equal(65, tonumber(res.headers["Content-Length"]))
      end)

      it("errors on bad region name (DNS resolution)", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get?key1=some_value1",
          headers = {
            ["Host"] = "lambda15.com"
          }
        })
        assert.res_status(500, res)

        helpers.wait_until(function()
          local logs = pl_file.read(TEST_CONF.prefix .. "/" .. TEST_CONF.proxy_error_log)
          local _, count = logs:gsub([[%[aws%-lambda%].+lambda%.ab%-cdef%-1%.amazonaws%.com.+name error"]], "")
          return count >= 1
        end, 10)
      end)

      describe("config.is_proxy_integration = true", function()


  -- here's where we miss the changes to the custom nginx template, to be able to
  -- run the tests against older versions (0.13.x) of Kong. Add those manually
  -- and the tests pass.
  -- see: https://github.com/Kong/kong/commit/c6f9e4558b5a654e78ca96b2ba4309e527053403#diff-9d13d8efc852de84b07e71bf419a2c4d

        it("sets proper status code on custom response from Lambda", function()
          local res = assert(proxy_client:send {
            method  = "POST",
            path    = "/post",
            headers = {
              ["Host"]         = "lambda11.com",
              ["Content-Type"] = "application/json"
            },
            body = {
              statusCode = 201,
            }
          })
          local body = assert.res_status(201, res)
          assert.equal(0, tonumber(res.headers["Content-Length"]))
          assert.equal(nil, res.headers["X-Custom-Header"])
          assert.equal("", body)
        end)

        it("sets proper status code/headers/body on custom response from Lambda", function()
          -- the lambda function must return a string
          -- for the custom response "body" property
          local body = cjson.encode({
            key1 = "some_value_post1",
            key2 = "some_value_post2",
            key3 = "some_value_post3",
          })

          local res = assert(proxy_client:send {
            method  = "POST",
            path    = "/post",
            headers = {
              ["Host"]         = "lambda11.com",
              ["Content-Type"] = "application/json",
            },
            body = {
              statusCode = 201,
              body = body,
              headers = {
                ["X-Custom-Header"] = "Hello world!"
              }
            }
          })

          local res_body = assert.res_status(201, res)
          assert.equal(79, tonumber(res.headers["Content-Length"]))
          assert.equal("Hello world!", res.headers["X-Custom-Header"])
          assert.equal(body, res_body)
        end)

        it("override duplicated headers with value from the custom response from Lambda", function()
          -- the default "x-amzn-RequestId" returned is "foo"
          -- let's check it is overriden with a custom value
          local headers = {
            ["x-amzn-RequestId"] = "bar",
          }

          local res = assert(proxy_client:send {
            method  = "POST",
            path    = "/post",
            headers = {
              ["Host"]         = "lambda11.com",
              ["Content-Type"] = "application/json",
            },
            body = {
              statusCode = 201,
              headers = headers,
            }
          })

          assert.res_status(201, res)
          assert.equal("bar", res.headers["x-amzn-RequestId"])
        end)

        it("returns HTTP 502 when 'status' property of custom response is not a number", function()
          local res = assert(proxy_client:send {
            method  = "POST",
            path    = "/post",
            headers = {
              ["Host"]         = "lambda11.com",
              ["Content-Type"] = "application/json",
            },
            body = {
              statusCode = "hello",
            }
          })

          assert.res_status(502, res)
          local b = assert.response(res).has.jsonbody()
          assert.equal("Bad Gateway", b.message)
        end)

        it("returns HTTP 502 when 'headers' property of custom response is not a table", function()
          local res = assert(proxy_client:send {
            method  = "POST",
            path    = "/post",
            headers = {
              ["Host"]         = "lambda11.com",
              ["Content-Type"] = "application/json",
            },
            body = {
              headers = "hello",
            }
          })

          assert.res_status(502, res)
          local b = assert.response(res).has.jsonbody()
          assert.equal("Bad Gateway", b.message)
        end)

        it("returns HTTP 502 when 'body' property of custom response is not a string", function()
          local res = assert(proxy_client:send {
            method  = "POST",
            path    = "/post",
            headers = {
              ["Host"]         = "lambda11.com",
              ["Content-Type"] = "application/json",
            },
            body = {
              statusCode = 201,
              body = 1234,
            }
          })

          assert.res_status(502, res)
          local b = assert.response(res).has.jsonbody()
          assert.equal("Bad Gateway", b.message)
        end)

        it("returns HTTP 502 with when response from lambda is not valid JSON", function()
          local res = assert(proxy_client:send {
            method  = "POST",
            path    = "/post",
            headers = {
              ["Host"] = "lambda12.com",
            }
          })

          assert.res_status(502, res)
          local b = assert.response(res).has.jsonbody()
          assert.equal("Bad Gateway", b.message)
        end)

        it("returns HTTP 502 on empty response from Lambda", function()
          local res = assert(proxy_client:send {
            method  = "POST",
            path    = "/post",
            headers = {
              ["Host"] = "lambda13.com",
            }
          })

          assert.res_status(502, res)
          local b = assert.response(res).has.jsonbody()
          assert.equal("Bad Gateway", b.message)
        end)

        it("invokes a Lambda function with GET using serviceless route", function()
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/get?key1=some_value1&key2=some_value2&key3=some_value3",
            headers = {
              ["Host"] = "lambda14.com"
            }
          })
          assert.res_status(200, res)
          local body = assert.response(res).has.jsonbody()
          assert.is_string(res.headers["x-amzn-RequestId"])
          assert.equal("some_value1", body.key1)
          assert.is_nil(res.headers["X-Amz-Function-Error"])
        end)

        it("returns decoded base64 response from a Lambda function", function()
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/get?key1=some_value1&key2=some_value2&key3=some_value3",
            headers = {
              ["Host"] = "lambda16.com"
            }
          })
          assert.res_status(200, res)
          assert.equal("test", res:read_body())
        end)

        it("returns multivalueheaders response from a Lambda function", function()
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/get?key1=some_value1&key2=some_value2&key3=some_value3",
            headers = {
              ["Host"] = "lambda17.com"
            }
          })
          assert.res_status(200, res)
          assert.is_string(res.headers.age)
          assert.is_array(res.headers["Access-Control-Allow-Origin"])
        end)
      end)

      it("fails when no region is set and no host is provided", function()
        local res = assert(proxy_client:send({
          method  = "GET",
          path    = "/get?key1=some_value1",
          headers = {
            ["Host"] = "lambda18.com"
          }
        }))
        assert.res_status(500, res)
      end)

      it("succeeds when region is set in config and not set in environment", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get?key1=some_value1&key2=some_value2&key3=some_value3",
          headers = {
            ["Host"] = "lambda.com"
          }
        })
        assert.res_status(200, res)
        local body = assert.response(res).has.jsonbody()
        assert.is_string(res.headers["x-amzn-RequestId"])
        assert.equal("some_value1", body.key1)
        assert.is_nil(res.headers["X-Amz-Function-Error"])
      end)

      it("succeeds when region and host are set in config", function()
        local res = assert(proxy_client:send({
          method  = "GET",
          path    = "/get?key1=some_value1&key2=some_value2&key3=some_value3",
          headers = {
            ["Host"] = "lambda20.com",
          }
        }))

        local body = assert.response(res).has.jsonbody()
        assert.is_string(res.headers["x-amzn-RequestId"])
        assert.equal("some_value1", body.key1)
        assert.is_nil(res.headers["X-Amz-Function-Error"])
      end)

      it("works with a forward proxy", function()
        local res = assert(proxy_client:send({
          method  = "GET",
          path    = "/get?a=1&b=2",
          headers = {
            ["Host"] = "lambda21.com"
          }
        }))

        assert.res_status(200, res)
        local req = assert.response(res).has.jsonbody()
        assert.equals("https", req.vars.scheme)
      end)

    end)

    describe("AWS_REGION environment is set", function()

      lazy_setup(function()
        helpers.setenv("AWS_REGION", "us-east-1")
        assert(helpers.start_kong({
          database   = strategy,
          plugins = "aws-lambda",
          nginx_conf = "spec/fixtures/custom_nginx.template",
          -- we don't actually use any stream proxy features in this test suite,
          -- but this is needed in order to load our forward-proxy stream_mock fixture
          stream_listen = helpers.get_proxy_ip(false) .. ":19000",
        }, nil, nil, fixtures))
      end)

      lazy_teardown(function()
        helpers.stop_kong()
        helpers.unsetenv("AWS_REGION", "us-east-1")
      end)

      it("use ENV value when no region nor host is set", function()
        local res = assert(proxy_client:send({
          method  = "GET",
          path    = "/get?key1=some_value1",
          headers = {
            ["Host"] = "lambda19.com"
          }
        }))
        assert.res_status(200, res)
        assert.is_string(res.headers.age)
        assert.is_array(res.headers["Access-Control-Allow-Origin"])
      end)
    end)
  end)
end
