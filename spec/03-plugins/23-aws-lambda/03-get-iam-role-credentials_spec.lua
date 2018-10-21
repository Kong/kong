local helpers = require "spec.helpers"
local get_credentials_from_iam_role = require "kong.plugins.aws-lambda.iam-role-credentials"

describe("Plugin: AWS Lambda (metadata service credentials)", function()
  setup(function()
    assert(helpers.start_kong {
      nginx_conf = "spec/fixtures/custom_nginx.template",
    })
  end)

  teardown(function()
    helpers.stop_kong()
  end)

  it("should return error if metadata service is not running on provided endpoint", function()
    local iam_role_credentials, err = get_credentials_from_iam_role('192.0.2.0', 1234, 200, 0)

    assert.is_nil(iam_role_credentials)
    assert.is_not_nil(err)
    assert.equal("timeout", err)
  end)

  it("should fetch credentials from metadata service", function()
    local iam_role_credentials, err = get_credentials_from_iam_role('127.0.0.1', 15555, 200, 0)

    assert.is_nil(err)
    assert.equal("test_iam_access_key_id", iam_role_credentials.access_key)
    assert.equal("test_iam_secret_access_key", iam_role_credentials.secret_key)
    assert.equal("test_session_token", iam_role_credentials.session_token)
  end)
end)
