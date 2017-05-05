local helpers = require "spec.helpers"

pending("Plugin: AWS Lambda (access)", function()
  -- pending due to AWS account issues and
  -- waiting for a mock solution as suggested by
  -- https://github.com/Mashape/kong/pull/2287
  local client, api_client

  setup(function()
    local api1 = assert(helpers.dao.apis:insert {
      name = "lambda.com",
      hosts = { "lambda.com" } ,
      upstream_url = "http://httpbin.org"
    })

    local api2 = assert(helpers.dao.apis:insert {
      name = "lambda2.com",
      hosts = { "lambda2.com" },
      upstream_url = "http://httpbin.org"
    })

    local api3 = assert(helpers.dao.apis:insert {
      name = "lambda3.com",
      hosts = { "lambda3.com" },
      upstream_url = "http://httpbin.org"
    })

    assert(helpers.dao.plugins:insert {
      name = "aws-lambda",
      api_id = api1.id,
      config = {
        aws_key = "AKIAIDPNYYGMJOXN26SQ",
        aws_secret = "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",
        aws_region = "us-east-1",
        function_name = "kongLambdaTest"
      }
    })

    assert(helpers.dao.plugins:insert {
      name = "aws-lambda",
      api_id = api2.id,
      config = {
        aws_key = "AKIAIDPNYYGMJOXN26SQ",
        aws_secret = "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",
        aws_region = "us-east-1",
        function_name = "kongLambdaTest",
        invocation_type = "Event"
      }
    })

    assert(helpers.dao.plugins:insert {
      name = "aws-lambda",
      api_id = api3.id,
      config = {
        aws_key = "AKIAIDPNYYGMJOXN26SQ",
        aws_secret = "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",
        aws_region = "us-east-1",
        function_name = "kongLambdaTest",
        invocation_type = "DryRun"
      }
    })

    assert(helpers.start_kong())

    -- Improve test reliability here: warm up AWS lambda because the first
    -- invocation will take the most time
    client = helpers.proxy_client()
    client:set_timeout(2 * 60 * 1000) -- 2 minute timeout for the warmup
    assert(client:send {
      method = "GET",
      path = "/get?key1=some_value1&key2=some_value2&key3=some_value3",
      headers = {
        ["Host"] = "lambda.com"
      }
    })
    client:close()
  end)

  before_each(function()
    client = helpers.proxy_client()
    api_client = helpers.admin_client()
  end)

  after_each(function ()
    client:close()
    api_client:close()
  end)

  teardown(function()
    helpers.stop_kong()
  end)

  it("invokes a Lambda function with GET", function()
    local res = assert(client:send {
      method = "GET",
      path = "/get?key1=some_value1&key2=some_value2&key3=some_value3",
      headers = {
        ["Host"] = "lambda.com"
      }
    })
    local body = assert.res_status(200, res)
    assert.is_string(res.headers["x-amzn-RequestId"])
    assert.equal([["some_value1"]], body)
  end)
  it("invokes a Lambda function with POST params", function()
    local res = assert(client:send {
      method = "POST",
      path = "/post",
      headers = {
        ["Host"] = "lambda.com",
        ["Content-Type"] = "application/x-www-form-urlencoded"
      },
      body = {
        key1 = "some_value_post1",
        key2 = "some_value_post2",
        key3 = "some_value_post3"
      }
    })
    local body = assert.res_status(200, res)
    assert.is_string(res.headers["x-amzn-RequestId"])
    assert.equal([["some_value_post1"]], body)
  end)
  it("invokes a Lambda function with POST json body", function()
    local res = assert(client:send {
      method = "POST",
      path = "/post",
      headers = {
        ["Host"] = "lambda.com",
        ["Content-Type"] = "application/json"
      },
      body = {
        key1 = "some_value_json1",
        key2 = "some_value_json2",
        key3 = "some_value_json3"
      }
    })
    local body = assert.res_status(200, res)
    assert.is_string(res.headers["x-amzn-RequestId"])
    assert.equal([["some_value_json1"]], body)
  end)
  it("invokes a Lambda function with POST and both querystring and body params", function()
    local res = assert(client:send {
      method = "POST",
      path = "/post?key1=from_querystring",
      headers = {
        ["Host"] = "lambda.com",
        ["Content-Type"] = "application/x-www-form-urlencoded"
      },
      body = {
        key2 = "some_value_post2",
        key3 = "some_value_post3"
      }
    })
    local body = assert.res_status(200, res)
    assert.is_string(res.headers["x-amzn-RequestId"])
    assert.equal([["from_querystring"]], body)
  end)
  it("invokes a Lambda function with POST params and Event invocation_type", function()
    local res = assert(client:send {
      method = "POST",
      path = "/post",
      headers = {
        ["Host"] = "lambda2.com",
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
    local res = assert(client:send {
      method = "POST",
      path = "/post",
      headers = {
        ["Host"] = "lambda3.com",
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

end)
