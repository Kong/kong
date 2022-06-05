require "spec.helpers"

describe("[AWS Lambda] iam-sts", function()

  local fetch_sts_assume_role, http_responses

  before_each(function()
    package.loaded["kong.plugins.aws-lambda.iam-sts-credentials"] = nil
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
    fetch_sts_assume_role = require("kong.plugins.aws-lambda.iam-sts-credentials").fetch_assume_role_credentials
  end)

  after_each(function()
  end)

  it("should fetch credentials from sts service", function()
    http_responses = {
      [[
{
  "AssumeRoleResponse": {
    "AssumeRoleResult": {
      "SourceIdentity": "kong_session",
      "AssumedRoleUser": {
        "Arn": "arn:aws:iam::000000000001:role/temp-role",
        "AssumedRoleId": "arn:aws:iam::000000000001:role/temp-role"
      },
      "Credentials": {
        "AccessKeyId": "the Access Key",
        "SecretAccessKey": "the Big Secret",
        "SessionToken": "the Token of Appreciation",
        "Expiration": 1552424170
      },
      "PackedPolicySize": 1000
    },
    "ResponseMetadata": {
      "RequestId": "c6104cbe-af31-11e0-8154-cbc7ccf896c7"
    }
  }
}
]]
    }

    local aws_region = "ap-east-1"
    local assume_role_arn = "arn:aws:iam::000000000001:role/temp-role"
    local role_session_name = "kong_session"
    local access_key = "test_access_key"
    local secret_key = "test_secret_key"
    local session_token = "test_session_token"
    local iam_role_credentials, err = fetch_sts_assume_role(aws_region, assume_role_arn, role_session_name, access_key, secret_key, session_token)

    assert.is_nil(err)
    assert.equal("the Access Key", iam_role_credentials.access_key)
    assert.equal("the Big Secret", iam_role_credentials.secret_key)
    assert.equal("the Token of Appreciation", iam_role_credentials.session_token)
    assert.equal(1552424170, iam_role_credentials.expiration)
  end)
end)
