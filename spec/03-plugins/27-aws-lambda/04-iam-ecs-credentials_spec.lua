local helpers = require "spec.helpers"

for _, strategy in helpers.each_strategy() do
  describe("[AWS Lambda] iam-ecs module environment variable fetch in Kong startup [#" .. strategy .. "]", function ()
    local proxy_client

    lazy_setup(function ()
      helpers.setenv("AWS_CONTAINER_CREDENTIALS_RELATIVE_URI", "/v2/credentials/unique-string-match-12344321")

      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
      }, { "aws-lambda", "file-log" })

      local service1 = bp.services:insert {
        host = "mockbin.org",
        port = 80,
      }

      local route1 = bp.routes:insert {
        hosts = { "lambda.com" },
        service = service1,
      }

      -- Add lambda plugin so that the module is loaded
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

      local service2 = bp.services:insert {
        host = "mockbin.org",
        port = 80,
      }

      local route2 = bp.routes:insert {
        hosts = { "lambda2.com" },
        service = service2,
      }


      bp.plugins:insert {
        name     = "file-log",
        route    = { id = route2.id },
        config   = {
          path = "test-aws-ecs-file.log",
          custom_fields_by_lua = {
            ecs_uri = "return package.loaded[\"kong.plugins.aws-lambda.iam-ecs-credentials\"]._ECS_URI"
          }
        },
      }

      assert(helpers.start_kong({
        database   = strategy,
        untrusted_lua = "on",
        plugins = "aws-lambda, file-log",
      }, nil, nil, nil))
    end)

    before_each(function()
      proxy_client = helpers.proxy_client()
    end)

    after_each(function ()
      proxy_client:close()
    end)

    lazy_teardown(function()
      helpers.stop_kong()
      helpers.unsetenv("AWS_CONTAINER_CREDENTIALS_RELATIVE_URI")
    end)

    it("should find ECS uri in the file log", function()
      helpers.clean_logfile("test-aws-ecs-file.log")

      assert(proxy_client:send {
        method = "GET",
        path = "/",
        headers = {
          host = "lambda2.com",
        }
      })

      assert.logfile("test-aws-ecs-file.log").has.line("unique-string-match-12344321", true, 20)
    end)
  end)
end

describe("[AWS Lambda] iam-ecs credential fetch test", function()

  local fetch_ecs, http_responses, env_vars
  local old_getenv = os.getenv

  before_each(function()
    package.loaded["kong.plugins.aws-lambda.iam-ecs-credentials"] = nil
    package.loaded["resty.http"] = nil
    local http = require "resty.http"
    -- mock the http module
    http.new = function()
      return {
        set_timeout = function() end,
        request_uri = function()
          local body = http_responses[1]
          table.remove(http_responses, 1)
          return {
            status = 200,
            body = body,
          }
        end,
      }
    end
    -- mock os.getenv
    os.getenv = function(name)  -- luacheck: ignore
      return (env_vars or {})[name] or old_getenv(name)
    end
  end)

  after_each(function()
    os.getenv = old_getenv  -- luacheck: ignore
  end)

  it("should fetch credentials from metadata service", function()
    env_vars = {
      AWS_CONTAINER_CREDENTIALS_RELATIVE_URI = "/just/a/path"
    }

    http_responses = {
      [[
{
  "Code" : "Success",
  "LastUpdated" : "2019-03-12T14:20:45Z",
  "Type" : "AWS-HMAC",
  "AccessKeyId" : "the Access Key",
  "SecretAccessKey" : "the Big Secret",
  "Token" : "the Token of Appreciation",
  "Expiration" : "2019-03-12T20:56:10Z"
}
]]
    }

    fetch_ecs = require("kong.plugins.aws-lambda.iam-ecs-credentials").fetchCredentials

    local iam_role_credentials, err = fetch_ecs()

    assert.is_nil(err)
    assert.equal("the Access Key", iam_role_credentials.access_key)
    assert.equal("the Big Secret", iam_role_credentials.secret_key)
    assert.equal("the Token of Appreciation", iam_role_credentials.session_token)
    assert.equal(1552424170, iam_role_credentials.expiration)
  end)
end)
