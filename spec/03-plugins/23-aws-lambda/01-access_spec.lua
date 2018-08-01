local helpers = require "spec.helpers"
local meta    = require "kong.meta"


local server_tokens = meta._SERVER_TOKENS


for _, strategy in helpers.each_strategy() do
  describe("Plugin: AWS Lambda (access) [#" .. strategy .. "]", function()
    local proxy_client
    local admin_client

    setup(function()
      local bp = helpers.get_db_utils(strategy)

      local route1 = bp.routes:insert {
        hosts = { "lambda.com" },
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
        service    = bp.services:insert({
          protocol = "http",
          host     = "httpbin.org",
          port     = 80,
        })
      }

      local service10 = bp.services:insert({
        protocol = "http",
        host     = "httpbin.org",
        port     = 80,
      })

      local route10 = bp.routes:insert {
        hosts       = { "lambda10.com" },
        protocols   = { "http", "https" },
        service     = service10
      }

      bp.plugins:insert {
        name     = "aws-lambda",
        route = { id = route1.id },
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
        route = { id = route2.id },
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
        route = { id = route3.id },
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
        route = { id = route4.id },
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
        route = { id = route5.id },
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
        route = { id = route6.id },
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
        route = { id = route7.id },
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
        route = { id = route8.id },
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
        route = { id = route9.id },
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
        route = { id = route10.id },
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

      assert(helpers.start_kong{
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
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

    teardown(function()
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
    it("invokes a Lambda function with POST and xml payload, custom header and query partameter", function()
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
    it("invokes a Lambda function with POST and json payload, custom header and query partameter", function()
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
    it("invokes a Lambda function with POST and txt payload, custom header and query partameter", function()
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

      assert.equal(server_tokens, res.headers["Via"])
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

  end)
end
