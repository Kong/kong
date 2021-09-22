require "spec.helpers"

describe("[AWS Lambda] iam-ecs", function()

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
