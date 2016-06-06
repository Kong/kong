local spec_helper = require "spec.spec_helpers"
local http_client = require "kong.tools.http_client"
local cjson = require('cjson')

local PROXY_URL = spec_helper.PROXY_URL

describe("AWS Lambda Plugin", function()

  setup(function()
    spec_helper.prepare_db()
    spec_helper.insert_fixtures {
      api = {
        {name = "tests-aws-lambda", request_host = "aws-lambda.com", upstream_url = "http://mockbin.com"},
        {name = "tests-aws-lambda-2", request_host = "aws-lambda-2.com", upstream_url = "aws-lambda://us-east-1/kongLambdaTest"},
        {name = "tests-aws-lambda-3", request_host = "aws-lambda-3.com", upstream_url = "aws-lambda://us-east-1/kongLambdaTest"},
        {name = "tests-aws-lambda-4", request_host = "aws-lambda-4.com", upstream_url = "aws-lambda://us-east-1/kongLambdaTest"},
        {name = "tests-aws-lambda-5", request_host = "aws-lambda-5.com", upstream_url = "aws-lambda://us-east-1/kongLambdaTest"},
        {name = "tests-aws-lambda-6", request_host = "aws-lambda-6.com", upstream_url = "aws-lambda://region/func"},
        {name = "tests-aws-lambda-7", request_host = "aws-lambda-7.com", upstream_url = "aws-lambda://region/func"},
        {name = "tests-aws-lambda-8", request_host = "aws-lambda-8.com", upstream_url = "aws-lambda://us-east-1/kongLambdaTest"}

      },
      plugin = {
        {name = "aws-lambda", config = {aws_region = "us-east-1", function_name = "kongLambdaTest", body = cjson.encode({key1="foo",key2="bar",key3="baz"}), aws_access_key = "AKIAIDPNYYGMJOXN26SQ", aws_secret_key = "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"}, __api = 1},
        {name = "aws-lambda", config = {aws_region = "us-east-1", function_name = "kongLambdaTest", body = cjson.encode({key1="foo",key2="bar",key3="baz"}), aws_access_key = "AKIAIDPNYYGMJOXN26SQ", aws_secret_key = "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"}, __api = 2},
        {name = "aws-lambda", config = {aws_region = "us-east-1", function_name = "kongLambdaTest", body = cjson.encode({key2="bar",key3="baz"}), aws_access_key = "AKIAIDPNYYGMJOXN26SQ", aws_secret_key = "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"}, __api = 3},
        {name = "aws-lambda", config = {aws_region = "us-east-1", function_name = "kongLambdaTest", body = cjson.encode({key3="baz"}), aws_access_key = "AKIAIDPNYYGMJOXN26SQ", aws_secret_key = "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"}, __api = 4},
        {name = "aws-lambda", config = {aws_region = "us-east-1", function_name = "kongLambdaTest", body = cjson.encode({key1="foo",key2="bar",key3="baz"})}, __api = 5},
        {name = "aws-lambda", config = {aws_region = "us-east-1", function_name = "func", body = cjson.encode({key1="foo",key2="bar",key3="baz"})}, __api = 6},
        {name = "aws-lambda", config = {aws_region = "region", function_name = "kongLambdaTest", body = cjson.encode({key1="foo",key2="bar",key3="baz"})}, __api = 7},
        {name = "aws-lambda", config = {body = cjson.encode({key1="foo",key2="bar",key3="baz"}), aws_access_key = "AKIAIDPNYYGMJOXN26SQ", aws_secret_key = "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"}, __api = 8}

      }
    }

    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
  end)

  describe("AWS Lambda plugin", function()

    describe("with all parameters defined in config", function ()

      it("should return informative 500 error when upstream_url is not aws-lambda scheme", function()
        local response, code, _ = http_client.get(PROXY_URL.."/", {}, {host = "aws-lambda.com"})
  
        assert.equal(500, code)
        assert.equal("Invalid upstream_url - must be 'aws-lambda'.", response)
      end)
  
      it("should return any x-amz-function-error", function()
        local response, status, _ = http_client.get(PROXY_URL.."/", {}, {host = "aws-lambda-3.com"})
        
	assert.equal(500, status)
        assert.is_true(response:find("KeyError") ~= nil)
      end)

      it("should include api querystring parameter in payload of lambda", function()
        local parm_value = "test-value"

        local response, status, _ = http_client.get(PROXY_URL.."/", {key1=parm_value}, {host = "aws-lambda-3.com"})

	assert.equal(200, status)
        assert.equal('"'..parm_value..'"', response)
      end)

      it("should include paramaters in body_data in payload of lambda", function()
        local parm_name = "key1"
        local parm_value = "foo"
        local body = {}
        body[parm_name] = parm_value

	local reqHeaders = {}
	reqHeaders["host"] = "aws-lambda-3.com"
	reqHeaders["content-type"] = "application/json"
        local response, _, _ = http_client.post(PROXY_URL.."/", body, reqHeaders)

        assert.equal('"'..parm_value..'"', response)
      end)

    end)

    describe("with credentials undefined in config", function()

      it("should accept key:secret in Authorization: basic header value", function()
        local key = "AKIAIDPNYYGMJOXN26SQ"
        local secret = "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"
	local mime = require "mime"
        local authHeader = "Basic "..mime.b64(key..":"..secret)

	local reqHeaders = {
		host = "aws-lambda-5.com",
                Authorization = authHeader
	}
        local response, _, _ = http_client.get(PROXY_URL.."/", {}, reqHeaders)

        assert.equal('"foo"', response)
      end)

    end)

    describe("with upstream_url different from config", function()

      it("should return 500 with informative message about mismatched region", function()
        local response, code, _ = http_client.get(PROXY_URL.."/", {}, { host = "aws-lambda-6.com" })

        assert.equal(500, code)
        assert.equal("aws-lambda plugin config aws_region (us-east-1) must match api upstream_url host (region)", response)
      end)

      it("should return 500 with informative message about mismatched function", function()
        local response, code, _ = http_client.get(PROXY_URL.."/", {}, { host = "aws-lambda-7.com" })

        assert.equal(500, code)
        assert.equal("aws-lambda plugin config function_name (kongLambdaTest) must match api upstream_url path (func)", response)
      end)

    end)

    describe("with no aws_region or function_name in config", function()

      it("should succeed using api upstream_url", function()
        local response, code, _ = http_client.get(PROXY_URL.."/", {}, { host = "aws-lambda-8.com" })

	--assert.equal(200, code)
        assert.equal('"foo"', response)
      end)

    end)

  end)

end)
