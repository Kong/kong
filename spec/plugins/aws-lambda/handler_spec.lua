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
        {name = "tests-aws-lambda-2", request_host = "aws-lambda-2.com", upstream_url = "aws-lambda://region/func"},
        {name = "tests-aws-lambda-3", request_host = "aws-lambda-3.com", upstream_url = "aws-lambda://region/func"},
        {name = "tests-aws-lambda-4", request_host = "aws-lambda-4.com", upstream_url = "aws-lambda://region/func"}
      },
      plugin = {
        {name = "aws-lambda", config = {aws_region = "us-east-1", function_name = "kongLambdaTest", body = cjson.encode({key1="foo",key2="bar",key3="baz"}), aws_access_key = "AKIAIDPNYYGMJOXN26SQ", aws_secret_key = "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"}, __api = 1},
        {name = "aws-lambda", config = {aws_region = "us-east-1", function_name = "kongLambdaTest", body = cjson.encode({key1="foo",key2="bar",key3="baz"}), aws_access_key = "AKIAIDPNYYGMJOXN26SQ", aws_secret_key = "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"}, __api = 2},
        {name = "aws-lambda", config = {aws_region = "us-east-1", function_name = "kongLambdaTest", body = cjson.encode({key2="bar",key3="baz"}), aws_access_key = "AKIAIDPNYYGMJOXN26SQ", aws_secret_key = "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"}, __api = 3},
        {name = "aws-lambda", config = {aws_region = "us-east-1", function_name = "kongLambdaTest", body = cjson.encode({key3="baz"}), aws_access_key = "AKIAIDPNYYGMJOXN26SQ", aws_secret_key = "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"}, __api = 4}
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
        local response, _, _ = http_client.get(PROXY_URL.."/", {}, {host = "aws-lambda.com"})
  
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

  end)

end)
