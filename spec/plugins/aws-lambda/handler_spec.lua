local _ = require "spec.spec_helpers"
local match = require("luassert.match")
local cjson = require('cjson')

describe("AWS Lambda Plugin", function()

  local handler

  local config
  local mockAwsv4
  local mockHttps
  local spyNgxPrint

  local test_req = {}

  local function setQueryParameter(key, value)
    test_req.query_parameters[key] = value
  end

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
    spyNgxPrint = spy.new(function() end)
    ngx.print = spyNgxPrint
    ngx.req = {
      get_uri_args = function() return test_req.query_parameters end
    }
    ngx.ctx.api = {
      upstream_url = "aws-lambda://foo-region/bar-function"
    }
    test_req = {
      query_parameters = {},
      body = nil
    }
    config = {
      aws_region = "us-west-2",
      function_name = "function_name",
      body = cjson.encode({foo=42}),
      access_key = "access key",
      secret_key = "secret key"
    }

    mockAwsv4 = {
      prepare_request = spy.new(function() return { url = "the_url" }, nil end)
    }
    mockHttps = {
      request = spy.new(function() return 1, 200, {}, "" end)
    }
    package.loaded['kong.plugins.aws-lambda.aws.v4'] = nil
    package.loaded['kong.plugins.aws-lambda.aws.v4'] = mockAwsv4
    package.loaded['ssl.https'] = nil
    package.loaded['ssl.https'] = mockHttps

    handler = require "kong.plugins.aws-lambda.handler"()
  end)

  after_each(function()
    package.loaded['kong.plugins.aws-lambda.handler'] = nil
    package.loaded['kong.plugins.aws-lambda.aws.v4'] = nil
    package.loaded['ssl.https'] = nil
  end)

  describe("AWS Lambda plugin", function()

    describe("with all parameters defined in config", function ()

      it("should return informative 500 error when upstream_url is not aws-lambda scheme", function()
        ngx.ctx.api.upstream_url = "http://foo.com"
  
        handler:access(config)
  
        assert.spy(spyNgxPrint).was_called_with(match.satisfies(
          function(val) return val == "Invalid upstream_url - must be 'aws-lambda'." end
        ))
      end)
  
      it("should call aws.v4.prepare_request with config values", function()
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
        handler:access(config)
        
        assert.spy(mockHttps.request).was_called()
      end)

      it("should include api querystring parameter in body of lambda", function()
        local parm_name = "foo_parm"
        local parm_value = "foo_value"
        setQueryParameter(parm_name, parm_value)

        handler:access(config)

        assert.spy(mockAwsv4.prepare_request).was_called_with(match.satisfies(
          function(opts)
            local body = cjson.decode(opts.body)
            return body[parm_name] == parm_value
          end
        ))
      end)

    end)

  end)

end)
