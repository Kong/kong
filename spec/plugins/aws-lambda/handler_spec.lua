local _ = require "spec.spec_helpers"
local match = require("luassert.match")

describe("AWS Lambda Plugin", function()

  local config = {
	  aws_region = "us-west-2",
	  function_name = "function_name",
	  body = "",
	  access_key = "access key",
	  secret_key = "secret key"
  }

  local mockAwsv4
  local mockHttps

  setup(function()
    mockAwsv4 = {
      prepare_request = spy.new(function() return { url = "the_url" }, nil end)
    }
    mockHttps = {
      request = spy.new(function() return { request = function() end } end)
    }
    package.loaded['kong.plugins.aws-lambda.aws.v4'] = nil
    package.loaded['kong.plugins.aws-lambda.aws.v4'] = mockAwsv4
    package.loaded['ssl.https'] = nil
    package.loaded['ssl.https'] = mockHttps

    local function satisfies(state, args)
      local func = args[1]
      return function (value)
        return func(value)
      end
    end

    assert:register("matcher", "satisfies", satisfies)      
  end)

  teardown(function()
    package.loaded['kong.plugins.aws-lambda.aws.v4'] = nil
  end)

  describe("AWS Lambda plugin", function()

    it("should call aws.v4.prepare_request with config values", function()
      local handler = require "kong.plugins.aws-lambda.handler"()

      handler:access(config)
      
      assert.spy(mockAwsv4.prepare_request).was.called_with(match.satisfies(
        function(opts) return opts.Region == config.aws_region end
      ))
      assert.spy(mockAwsv4.prepare_request).was.called_with(match.satisfies(
        function(opts) return string.find(opts.path, config.function_name) ~= nil end
      ))
      assert.spy(mockAwsv4.prepare_request).was.called_with(match.satisfies(
        function(opts) return opts.headers['Content-Length'] == tostring(string.len(config.body)) end
      ))
      assert.spy(mockAwsv4.prepare_request).was.called_with(match.satisfies(
        function(opts) return opts.body == config.body end
      ))
      assert.spy(mockAwsv4.prepare_request).was.called_with(match.satisfies(
        function(opts) return opts.AccessKey == config.aws_access_key end
      ))
      assert.spy(mockAwsv4.prepare_request).was.called_with(match.satisfies(
        function(opts) return opts.SecretKey == config.aws_secret_key end
      ))

    end)

    it("should call ssl.https.request", function()
      local handler = require "kong.plugins.aws-lambda.handler"()

      handler:access(config)
      
      assert.spy(mockHttps.request).was_called()

    end)

  end)

end)
