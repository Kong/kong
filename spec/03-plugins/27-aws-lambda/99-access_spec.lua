local cjson   = require "cjson"
local helpers = require "spec.helpers"
local meta    = require "kong.meta"
local pl_file = require "pl.file"
local fixtures = require "spec.fixtures.aws-lambda"
local http_mock = require "spec.helpers.http_mock"

local TEST_CONF = helpers.test_conf
local server_tokens = meta._SERVER_TOKENS
local null = ngx.null
local fmt = string.format



for _, strategy in helpers.each_strategy() do
  describe("Plugin: AWS Lambda (access) [#" .. strategy .. "]", function()
    local proxy_client
    local admin_client
    local mock_http_server_port = helpers.get_available_port()

    local mock = http_mock.new(mock_http_server_port, [[
      ngx.print('hello world')
    ]],  {
      prefix = "mockserver",
      log_opts = {
        req = true,
        req_body = true,
        req_large_body = true,
      },
      tls = false,
    })

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
      }, { "aws-lambda" })

      local route1 = bp.routes:insert {
        hosts = { "lambda.test" },
      }

      local route1_1 = bp.routes:insert {
        hosts   = { "lambda_ignore_service.test" },
        service = assert(bp.services:insert()),
      }

      local route2 = bp.routes:insert {
        hosts = { "lambda2.test" },
      }

      local route3 = bp.routes:insert {
        hosts = { "lambda3.test" },
      }

      local route4 = bp.routes:insert {
        hosts = { "lambda4.test" },
      }

      local route5 = bp.routes:insert {
        hosts = { "lambda5.test" },
      }

      local route6 = bp.routes:insert {
        hosts = { "lambda6.test" },
      }

      local route7 = bp.routes:insert {
        hosts = { "lambda7.test" },
      }

      local route8 = bp.routes:insert {
        hosts = { "lambda8.test" },
      }

      local route9 = bp.routes:insert {
        hosts      = { "lambda9.test" },
        protocols  = { "http", "https" },
        service    = null,
      }

      local route10 = bp.routes:insert {
        hosts       = { "lambda10.test" },
        protocols   = { "http", "https" },
        service     = null,
      }

      local route11 = bp.routes:insert {
        hosts       = { "lambda11.test" },
        protocols   = { "http", "https" },
        service     = null,
      }

      local route12 = bp.routes:insert {
        hosts       = { "lambda12.test" },
        protocols   = { "http", "https" },
        service     = null,
      }

      local route13 = bp.routes:insert {
        hosts       = { "lambda13.test" },
        protocols   = { "http", "https" },
        service     = null,
      }

      local route14 = bp.routes:insert {
        hosts       = { "lambda14.test" },
        protocols   = { "http", "https" },
        service     = null,
      }

      local route15 = bp.routes:insert {
        hosts       = { "lambda15.test" },
        protocols   = { "http", "https" },
        service     = null,
      }

      local route16 = bp.routes:insert {
        hosts       = { "lambda16.test" },
        protocols   = { "http", "https" },
        service     = null,
      }

      local route17 = bp.routes:insert {
        hosts       = { "lambda17.test" },
        protocols   = { "http", "https" },
        service     = null,
      }

      local route18 = bp.routes:insert {
        hosts       = { "lambda18.test" },
        protocols   = { "http", "https" },
        service     = null,
      }

      local route19 = bp.routes:insert {
        hosts       = { "lambda19.test" },
        protocols   = { "http", "https" },
        service     = null,
      }

      local route20 = bp.routes:insert {
        hosts       = { "lambda20.test" },
        protocols   = { "http", "https" },
        service     = null,
      }

      local route21 = bp.routes:insert {
        hosts       = { "lambda21.test" },
        protocols   = { "http", "https" },
        service     = null,
      }

      local route22 = bp.routes:insert {
        hosts       = { "lambda22.test" },
        protocols   = { "http", "https" },
        service     = null,
      }

      local route23 = bp.routes:insert {
        hosts       = { "lambda23.test" },
        protocols   = { "http", "https" },
        service     = null,
      }

      local route24 = bp.routes:insert {
        hosts       = { "lambda24.test" },
        protocols   = { "http", "https" },
        service     = null,
      }

      local route25 = bp.routes:insert {
        hosts       = { "lambda25.test" },
        protocols   = { "http", "https" },
        service     = null,
      }

      local route26 = bp.routes:insert {
        hosts       = { "lambda26.test" },
        protocols   = { "http", "https" },
        service     = null,
      }

      local route27 = bp.routes:insert {
        hosts       = { "lambda27.test" },
        protocols   = { "http", "https" },
        service     = null,
      }

      local route28 = bp.routes:insert {
        hosts       = { "lambda28.test" },
        protocols   = { "http", "https" },
        service     = null,
      }

      local route29 = bp.routes:insert {
        hosts       = { "lambda29.test" },
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

      bp.plugins:insert {
        name     = "aws-lambda",
        route    = { id = route22.id },
        config                 = {
          port                 = 10001,
          aws_key              = "mock-key",
          aws_secret           = "mock-secret",
          aws_region           = "us-east-1",
          function_name        = "functionWithIllegalBase64EncodedResponse",
          is_proxy_integration = true,
        }
      }

      bp.plugins:insert {
        name     = "aws-lambda",
        route    = { id = route23.id },
        config                 = {
          port                 = 10001,
          aws_key              = "mock-key",
          aws_secret           = "mock-secret",
          aws_region           = "us-east-1",
          function_name        = "functionWithNotBase64EncodedResponse",
          is_proxy_integration = true,
        }
      }

      bp.plugins:insert {
        name     = "aws-lambda",
        route    = { id = route24.id },
        config                 = {
          port                 = 10001,
          aws_key              = "mock-key",
          aws_secret           = "mock-secret",
          aws_region           = "us-east-1",
          function_name        = "functionWithTransferEncodingHeader",
          is_proxy_integration = true,
        }
      }

      bp.plugins:insert {
        name     = "aws-lambda",
        route    = { id = route25.id },
        config                 = {
          port                 = 10001,
          aws_key              = "mock-key",
          aws_secret           = "mock-secret",
          aws_region           = "us-east-1",
          function_name        = "functionWithLatency",
        }
      }

      bp.plugins:insert {
        route = { id = route25.id },
        name = "http-log",
        config   = {
          http_endpoint = "http://localhost:" .. mock_http_server_port,
        }
      }

      bp.plugins:insert {
        name     = "aws-lambda",
        route    = { id = route26.id },
        config                 = {
          port                 = 10001,
          aws_key              = "mock-key",
          aws_secret           = "mock-secret",
          aws_region           = "us-east-1",
          function_name        = "functionWithEmptyArray",
          empty_arrays_mode    = "legacy",
        }
      }

      bp.plugins:insert {
        name     = "aws-lambda",
        route    = { id = route27.id },
        config                 = {
          port                 = 10001,
          aws_key              = "mock-key",
          aws_secret           = "mock-secret",
          aws_region           = "us-east-1",
          function_name        = "functionWithEmptyArray",
          empty_arrays_mode    = "correct",
        }
      }

      bp.plugins:insert {
        name     = "aws-lambda",
        route    = { id = route28.id },
        config                 = {
          port                 = 10001,
          aws_key              = "mock-key",
          aws_secret           = "mock-secret",
          aws_region           = "us-east-1",
          function_name        = "functionWithArrayCTypeInMVHAndEmptyArray",
          empty_arrays_mode    = "legacy",
          is_proxy_integration = true,
        }
      }

      bp.plugins:insert {
        name     = "aws-lambda",
        route    = { id = route29.id },
        config                 = {
          port                 = 10001,
          aws_key              = "mock-key",
          aws_secret           = "mock-secret",
          aws_region           = "us-east-1",
          function_name        = "functionWithNullMultiValueHeaders",
          is_proxy_integration = true,
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
          plugins = "aws-lambda, http-log",
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
            ["Host"] = "lambda.test"
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
            ["Host"] = "lambda_ignore_service.test"
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
            ["Host"]         = "lambda.test",
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
            ["Host"]         = "lambda.test",
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
            ["Host"]         = "lambda.test",
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
            ["Host"]         = "lambda.test",
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
            ["Host"]          = "lambda9.test",
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
        assert.equal("lambda9.test", body.request_headers.host)

        -- request_body
        assert.equal("<xml/>", body.request_body)
        assert.is_table(body.request_body_args)
      end)

      it("invokes a Lambda function with POST and json payload, custom header and query parameter", function()
        local res = assert(proxy_client:send {
          method  = "POST",
          path    = "/post?key1=from_querystring",
          headers = {
            ["Host"]          = "lambda10.test",
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
        assert.equal("lambda10.test", body.request_headers.host)
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
            ["Host"]          = "lambda9.test",
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
        assert.equal("lambda9.test", body.request_headers.host)

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
            ["Host"]          = "lambda9.test",
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
        assert.equal("lambda9.test", body.request_headers.host)
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
            ["Host"]         = "lambda2.test",
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
            ["Host"]         = "lambda3.test",
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
            ["Host"] = "lambda4.test",
          }
        })
        assert.res_status(500, res)
      end)

      it("invokes a Lambda function with an unhandled function error (and no unhandled_status set)", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get?key1=some_value1&key2=some_value2&key3=some_value3",
          headers = {
            ["Host"] = "lambda5.test"
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
            ["Host"] = "lambda6.test"
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
            ["Host"] = "lambda7.test"
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
            ["Host"] = "lambda8.test"
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
            ["Host"] = "lambda.test"
          }
        })

        if server_tokens then
          assert.equal("2 " .. server_tokens, res.headers["Via"])
        end
      end)

      it("returns Content-Length header", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get?key1=some_value1&key2=some_value2&key3=some_value3",
          headers = {
            ["Host"] = "lambda.test"
          }
        })

        assert.equal(65, tonumber(res.headers["Content-Length"]))
      end)

      it("errors on bad region name (DNS resolution)", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get?key1=some_value1",
          headers = {
            ["Host"] = "lambda15.test"
          }
        })
        assert.res_status(500, res)

        helpers.wait_until(function()
          local logs = pl_file.read(TEST_CONF.prefix .. "/" .. TEST_CONF.proxy_error_log)
          local _, count = logs:gsub([[%[aws%-lambda%].+lambda%.ab%-cdef%-1%.amazonaws%.com.+name error"]], "")
          return count >= 1
        end, 10)
      end)

      it("invokes a Lambda function with empty array", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            ["Host"] = "lambda26.test"
          }
        })

        local body = assert.res_status(200, res)
        assert.matches("\"testbody\":{}", body)

        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            ["Host"] = "lambda27.test"
          }
        })

        local body = assert.res_status(200, res)
        assert.matches("\"testbody\":%[%]", body)
      end)

      it("invokes a Lambda function with legacy empty array mode and mutlivalueheaders", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            ["Host"] = "lambda28.test"
          }
        })

        local _ = assert.res_status(200, res)
        assert.equal("application/json+test", res.headers["Content-Type"])
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
              ["Host"]         = "lambda11.test",
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
              ["Host"]         = "lambda11.test",
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
              ["Host"]         = "lambda11.test",
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
              ["Host"]         = "lambda11.test",
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
              ["Host"]         = "lambda11.test",
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
              ["Host"]         = "lambda11.test",
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

        it("do not throw error when 'multiValueHeaders' is JSON null", function ()
          local res = assert(proxy_client:send {
            method  = "POST",
            path    = "/post",
            headers = {
              ["Host"]         = "lambda11.test",
              ["Content-Type"] = "application/json",
            },
            body = {
              statusCode = 201,
              body = "test",
              multiValueHeaders = cjson.null,
            }
          })

          local body = assert.res_status(201, res)
          assert.same(body, "test")
        end)

        it("returns HTTP 502 with when response from lambda is not valid JSON", function()
          local res = assert(proxy_client:send {
            method  = "POST",
            path    = "/post",
            headers = {
              ["Host"] = "lambda12.test",
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
              ["Host"] = "lambda13.test",
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
              ["Host"] = "lambda14.test"
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
              ["Host"] = "lambda16.test"
            }
          })
          assert.res_status(200, res)
          assert.equal("test", res:read_body())
        end)

        it("returns error response when isBase64Encoded is illegal from a Lambda function", function()
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/get?key1=some_value1&key2=some_value2&key3=some_value3",
            headers = {
              ["Host"] = "lambda22.test"
            }
          })
          assert.res_status(502, res)
          assert.is_true(not not string.find(res:read_body(), "isBase64Encoded must be a boolean"))
        end)

        it("returns raw body when isBase64Encoded is set to false from a Lambda function", function()
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/get?key1=some_value1&key2=some_value2&key3=some_value3",
            headers = {
              ["Host"] = "lambda23.test"
            }
          })
          assert.res_status(200, res)
          assert.equal("dGVzdA=", res:read_body())
        end)

        it("returns multivalueheaders response from a Lambda function", function()
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/get?key1=some_value1&key2=some_value2&key3=some_value3",
            headers = {
              ["Host"] = "lambda17.test"
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
            ["Host"] = "lambda18.test"
          }
        }))
        assert.res_status(500, res)
      end)

      it("succeeds when region is set in config and not set in environment", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get?key1=some_value1&key2=some_value2&key3=some_value3",
          headers = {
            ["Host"] = "lambda.test"
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
            ["Host"] = "lambda20.test",
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
            ["Host"] = "lambda21.test"
          }
        }))

        assert.res_status(200, res)
        local req = assert.response(res).has.jsonbody()
        assert.equals("https", req.vars.scheme)
      end)

      it("#test2 works normally by removing transfer encoding header when proxy integration mode", function ()
        proxy_client:set_timeout(3000)
        assert.eventually(function ()
          local res = assert(proxy_client:send({
            method  = "GET",
            path    = "/get",
            headers = {
              ["Host"] = "lambda24.test"
            }
          }))

          assert.res_status(200, res)
          assert.is_nil(res.headers["Transfer-Encoding"])
          assert.is_nil(res.headers["transfer-encoding"])

          return true
        end).with_timeout(3).is_truthy()
      end)
    end)

    describe("AWS_REGION environment is set", function()

      lazy_setup(function()
        helpers.setenv("AWS_REGION", "us-east-1")
        assert(helpers.start_kong({
          database   = strategy,
          plugins = "aws-lambda, http-log",
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
            ["Host"] = "lambda19.test"
          }
        }))
        assert.res_status(200, res)
        assert.is_string(res.headers.age)
        assert.is_array(res.headers["Access-Control-Allow-Origin"])
      end)
    end)

    describe("With latency", function()
      lazy_setup(function()
        assert(mock:start())

        helpers.setenv("AWS_REGION", "us-east-1")
        assert(helpers.start_kong({
          database   = strategy,
          plugins = "aws-lambda, http-log",
          nginx_conf = "spec/fixtures/custom_nginx.template",
          -- we don't actually use any stream proxy features in this test suite,
          -- but this is needed in order to load our forward-proxy stream_mock fixture
          stream_listen = helpers.get_proxy_ip(false) .. ":19000",
        }, nil, nil, fixtures))
      end)

      lazy_teardown(function()
        helpers.stop_kong()
        helpers.unsetenv("AWS_REGION")
        assert(mock:stop())
      end)

      it("invokes a Lambda function with GET and latency", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            ["Host"] = "lambda25.test"
          }
        })

        assert.res_status(200, res)
        local http_log_entries
        assert.eventually(function ()
          http_log_entries = mock:get_all_logs()
          return #http_log_entries >= 1
        end).with_timeout(10).is_truthy()
        assert.is_not_nil(http_log_entries[1])
        local log_entry_with_latency = cjson.decode(http_log_entries[1].req.body)
        -- Accessing the aws mock server will require some time for sure
        -- So if latencies.kong < latencies.proxy we should assume that the
        -- latency calculation is working. Checking a precise number will
        -- result in flakiness here.
        assert.True(log_entry_with_latency.latencies.kong < log_entry_with_latency.latencies.proxy)
      end)
    end)
  end)

  describe("Plugin: AWS Lambda with #vault [#" .. strategy .. "]", function ()
    local proxy_client
    local admin_client

    local ttl_time = 1

    lazy_setup(function ()
      helpers.setenv("KONG_VAULT_ROTATION_INTERVAL", "1")

      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
        "vaults",
      }, { "aws-lambda" }, { "random" })

      local route1 = bp.routes:insert {
        hosts = { "lambda-vault.test" },
      }

      bp.plugins:insert {
        name     = "aws-lambda",
        route    = { id = route1.id },
        config   = {
          port          = 10001,
          aws_key       = fmt("{vault://random/aws_key?ttl=%s&resurrect_ttl=0}", ttl_time),
          aws_secret    = "aws_secret",
          aws_region    = "us-east-1",
          function_name = "functionEcho",
        },
      }

      assert(helpers.start_kong({
        database       = strategy,
        prefix = helpers.test_conf.prefix,
        nginx_conf     = "spec/fixtures/custom_nginx.template",
        vaults         = "random",
        plugins        = "bundled",
        log_level      = "error",
      }, nil, nil, fixtures))
    end)

    lazy_teardown(function()
      helpers.unsetenv("KONG_VAULT_ROTATION_INTERVAL")

      helpers.stop_kong()
    end)

    before_each(function()
      proxy_client = helpers.proxy_client()
      admin_client = helpers.admin_client()
    end)

    after_each(function ()
      proxy_client:close()
      admin_client:close()
    end)

    it("lambda service should use latest reference value after Vault ttl", function ()
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/get?key1=some_value1&key2=some_value2&key3=some_value3",
        headers = {
          ["Host"] = "lambda-vault.test"
        }
      })
      assert.res_status(200, res)
      local body = assert.response(res).has.jsonbody()
      local authorization_header = body.headers.authorization
      local first_aws_key = string.match(authorization_header, "Credential=(.+)/")

      assert.eventually(function()
        proxy_client:close()
        proxy_client = helpers.proxy_client()

        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get?key1=some_value1&key2=some_value2&key3=some_value3",
          headers = {
            ["Host"] = "lambda-vault.test"
          }
        })
        assert.res_status(200, res)
        local body = assert.response(res).has.jsonbody()
        local authorization_header = body.headers.authorization
        local second_aws_key = string.match(authorization_header, "Credential=(.+)/")

        return first_aws_key ~= second_aws_key
      end).ignore_exceptions(true).with_timeout(ttl_time * 2).is_truthy()
    end)
  end)
end
