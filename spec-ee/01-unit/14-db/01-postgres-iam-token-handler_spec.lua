-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require("spec.helpers")

local iam_token_handler = require("kong.db.strategies.postgres.iam_token_handler")

local DB_ENDPOINT = "test_database.test_cluster.us-east-1.rds.amazonaws.com"
local DB_PORT = "443"
local DB_USER = "test_user"

local mock_config = {
  host = DB_ENDPOINT,
  port = DB_PORT,
  user = DB_USER,
  database = "kong-db",
}

describe("Postgres IAM token handler", function()
  local origin_time
  setup(function()
    package.loaded["resty.aws"] = nil
    package.loaded["resty.aws.config"] = nil
    origin_time = ngx.time
    ngx.time = function () --luacheck: ignore
      return 1667543171
    end
    helpers.setenv("AWS_REGION", "us-east-1")
    helpers.setenv("AWS_ACCESS_KEY_ID", "test_id")
    helpers.setenv("AWS_SECRET_ACCESS_KEY", "test_key")
    iam_token_handler.init()
  end)

  teardown(function ()
    ngx.time = origin_time --luacheck: ignore
    helpers.unsetenv("AWS_REGION")
    helpers.unsetenv("AWS_ACCESS_KEY_ID")
    helpers.unsetenv("AWS_SECRET_ACCESS_KEY")
  end)

  it("should generate expected token with mocking env", function()
    local token, err = iam_token_handler.get(mock_config)
    local expected_auth_token = "test_database.test_cluster.us-east-1.rds.amazonaws.com:443/?X-Amz-Signature=ff72d46f1937c1f5917f69d694929ca814b781619b8d730451c7ffef050059b0&Action=connect&DBUser=test_user&X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=test_id%2F20221104%2Fus-east-1%2Frds-db%2Faws4_request&X-Amz-Date=20221104T062611Z&X-Amz-Expires=900&X-Amz-SignedHeaders=host"

    assert.is_nil(err)
    assert.same(token, expected_auth_token)
  end)
end)
