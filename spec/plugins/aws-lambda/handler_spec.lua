local _ = require "spec.spec_helpers"
local match = require("luassert.match")

describe("AWS Lambda Plugin", function()

  local config
  local mockAwsv4
  local mockHttps
  local spyNgxPrint

  setup(function()
    local function satisfies(state, args)
      local func = args[1]
      return function (value)
        return func(value)
      end
    end

    assert:register("matcher", "satisfies", satisfies)      
  end)

  before_each(function()
    ngx.ctx.api = {
      upstream_url = "aws-lambda://foo-region/bar-function"
    }
    config = {
	  aws_region = "us-west-2",
	  function_name = "function_name",
	  body = "",
	  access_key = "access key",
	  secret_key = "secret key"
    }

    mockAwsv4 = {
      prepare_request = spy.new(function() return { url = "the_url" }, nil end)
    }
    mockHttps = {
      request = spy.new(function() return { request = function() end } end)
    }
    spyNgxPrint = spy.new(function() end)
    ngx.print = spyNgxPrint
    package.loaded['kong.plugins.aws-lambda.aws.v4'] = nil
    package.loaded['kong.plugins.aws-lambda.aws.v4'] = mockAwsv4
    package.loaded['ssl.https'] = nil
    package.loaded['ssl.https'] = mockHttps
  end)

  after_each(function()
    package.loaded['kong.plugins.aws-lambda.handler'] = nil
    package.loaded['kong.plugins.aws-lambda.aws.v4'] = nil
    package.loaded['ssl.https'] = nil
  end)

  describe("AWS Lambda plugin", function()

    it("should return informative 500 error when upstream_url is not aws-lambda scheme", function()
      local handler = require "kong.plugins.aws-lambda.handler"()
      ngx.ctx.api.upstream_url = "http://foo.com"

      handler:access(config)

      assert.spy(spyNgxPrint).was_called_with(match.satisfies(
        function(val) return val == "Invalid upstream_url - must be 'aws-lambda'." end
      ))
    end)

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
