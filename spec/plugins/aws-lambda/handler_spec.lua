local LambdaService = require "kong.plugins.aws-lambda.api-gateway.aws.lambda.LambdaService"
local spec_helper = require "spec.spec_helpers"
local utils = require "kong.tools.utils"
local http_client = require "kong.tools.http_client"
local cjson = require "cjson"
local rex = require "rex_pcre"

-- Load everything we need from the spec_helper
local env = spec_helper.get_env() -- test environment
local dao_factory = env.dao_factory

local PROXY_SSL_URL = spec_helper.PROXY_SSL_URL
local PROXY_URL = spec_helper.PROXY_URL
local STUB_GET_URL = spec_helper.STUB_GET_URL
local STUB_POST_URL = spec_helper.STUB_POST_URL

describe("AWS Lambda Plugin", function()

  setup(function()
    print("config", cjson.encode(env.conf_file))
    spec_helper.prepare_db()
    spec_helper.insert_fixtures {
      api = {
        { name = "test-lamba-api", request_host = "aws-lambda-test.com", upstream_url = "aws-lambda://test-region/test-function" },
      },
      plugin = {
        { name = "aws-lambda", config = { aws_region = "aws region", function_name = "function name", aws_access_key = "access key", aws_secret_key = "secret key" }, __api = 1 }
      }
    }
    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
  end)

  describe("AWS Lambda plugin", function()

    it("should be added", function()
      local realLambdaNew = LambdaService.new
      print("---->", realLambdaNew)
      local invokeSpy = spy.new(function () end)
      local function newFake() return { invoke = invokeSpy } end
      local newSpy = spy.on(newFake)
      lambda.new = function() print("boo") end
      --local response, status, headers = http_client.post(PROXY_SSL_URL.."/", { }, {host = "aws-lambda-test.com"})
      --local body = cjson.decode(response)
      
      --assert.are.equal(200, status)
      --assert.are.equal(2, utils.table_size(body))
      --assert.are.equal("invalid_provision_key", body.error)
      --assert.are.equal("Invalid Kong provision_key", body.error_description)

      ---- Checking headers
      --assert.are.equal("no-store", headers["cache-control"])
      --assert.are.equal("no-cache", headers["pragma"])
    end)

  end)

end)
