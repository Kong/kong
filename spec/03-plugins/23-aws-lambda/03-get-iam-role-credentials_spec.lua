local helpers = require "spec.helpers"
local get_credentials_from_iam_role = require "kong.plugins.aws-lambda.iam-role-credentials"

describe("Plugin: aws-lambda", function()
    setup(function()
        assert(helpers.start_kong{
            nginx_conf = "spec/fixtures/custom_nginx.template",
        })
    end)

    teardown(function()
        helpers.stop_kong()
    end)

    describe("IAM Metadata service", function()
        it("should fetch credentials from metadata service", function()
            local iam_role_credentials = get_credentials_from_iam_role('127.0.0.1', 9999)

            assert.equal("test_iam_access_key_id", iam_role_credentials.access_key)
            assert.equal("test_iam_secret_access_key", iam_role_credentials.secret_key)
            assert.equal("test_session_token", iam_role_credentials.session_token)
        end)
    end)
end)
