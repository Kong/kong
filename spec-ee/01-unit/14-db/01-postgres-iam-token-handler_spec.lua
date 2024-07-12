-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local DB_ENDPOINT = "test_database.test_cluster.us-east-1.rds.amazonaws.com"
local DB_PORT = "443"
local DB_USER = "test_user"

local mock_config = {
  host = DB_ENDPOINT,
  port = DB_PORT,
  user = DB_USER,
  database = "kong-db",
}

local mock_config_2 = {
  host = DB_ENDPOINT,
  port = DB_PORT,
  user = DB_USER,
  database = "kong-db-2",
}

local mock_config_assume_role = {
  host = DB_ENDPOINT,
  port = DB_PORT,
  user = DB_USER,
  database = "kong-db",
  iam_auth_assume_role_arn = "aws::arn::12345678::test-role",
  iam_auth_role_session_name = "test-session",
}

local mock_config_assume_role_with_sts_endpoint = {
  host = DB_ENDPOINT,
  port = DB_PORT,
  user = DB_USER,
  database = "kong-db",
  iam_auth_assume_role_arn = "aws::arn::12345678::test-role",
  iam_auth_role_session_name = "test-session",
  iam_auth_sts_endpoint_url = "https://vpce-1234567-abcdefg.sts.us-east-1.vpce.amazonaws.com"
}

local environment_credential_expire = 10*365*24*60*60

local resty_http_parse_uri = require("resty.http").parse_uri

local is_custom_sts_endpoint_flag = false

local resty_http = {
  parse_uri = resty_http_parse_uri,
  new = function()
    return {
      connect = function() return true end,
      close = function() return true end,
      set_timeout = function() return true end,
      set_timeouts = function() return true end,
      request = function(self, opts)
        if ("https://" .. opts.headers["Host"]) == mock_config_assume_role_with_sts_endpoint.iam_auth_sts_endpoint_url then
          is_custom_sts_endpoint_flag = true
        end

        return {
          status = 200,
          headers = {
            ["Content-Type"] = "application/xml",
          },
          has_body = true,
          body = [[<AssumeRoleResponse xmlns="https://sts.amazonaws.com/doc/2011-06-15/">
<AssumeRoleResult>
<SourceIdentity>Alice</SourceIdentity>
  <Credentials>
    <AccessKeyId>test_access_key</AccessKeyId>
    <SecretAccessKey>test_secret_key</SecretAccessKey>
    <SessionToken>
      test_session_token
    </SessionToken>
    <Expiration>2030-01-01T20:00:00Z</Expiration>
  </Credentials>
</AssumeRoleResult>
<ResponseMetadata>
  <RequestId>c6104cbe-af31-11e0-8154-cbc7ccf896c7</RequestId>
</ResponseMetadata>
</AssumeRoleResponse>
]],
          read_body = function(self) return self.body end,
        }
      end,
    }
  end,
}

package.loaded["resty.http"] = resty_http
package.loaded["resty.luasocket.http"] = resty_http


-- We only use setenv in helpers so it should not be a problem we patch the global resty http client
local helpers = require("spec.helpers")

describe("Postgres IAM token handler", function()
  local origin_time
  local origin_now
  local iam_token_handler
  setup(function()
    package.loaded["resty.aws"] = nil
    package.loaded["resty.aws.config"] = nil
    package.loaded["kong.db.strategies.postgres.iam_token_handler"] = nil
    package.loaded["resty.http"] = nil
    package.loaded["resty.luasocket.http"] = resty_http

    iam_token_handler = require("kong.db.strategies.postgres.iam_token_handler")
    origin_time = ngx.time
    origin_now = ngx.now
    ngx.time = function () --luacheck: ignore
      return 1667543171
    end
    ngx.now = function () --luacheck: ignore
      return 1667543171.0
    end
    helpers.setenv("AWS_REGION", "us-east-1")
    helpers.setenv("AWS_ACCESS_KEY_ID", "test_id")
    helpers.setenv("AWS_SECRET_ACCESS_KEY", "test_key")
    iam_token_handler.init()
  end)

  teardown(function ()
    ngx.time = origin_time --luacheck: ignore
    ngx.now = origin_now --luacheck: ignore
    helpers.unsetenv("AWS_REGION")
    helpers.unsetenv("AWS_ACCESS_KEY_ID")
    helpers.unsetenv("AWS_SECRET_ACCESS_KEY")
    package.loaded["resty.aws"] = nil
    package.loaded["resty.aws.config"] = nil
    package.loaded["resty.http"] = nil
    package.loaded["kong.db.strategies.postgres.iam_token_handler"] = nil
    package.loaded["resty.luasocket.http"] = nil
  end)

  before_each(function()
    is_custom_sts_endpoint_flag = false
  end)

  it("should generate expected token with mocking env", function()
    local token, err = iam_token_handler.get(mock_config)
    local expected_auth_token = "test_database.test_cluster.us-east-1.rds.amazonaws.com:443/?X-Amz-Signature=ff72d46f1937c1f5917f69d694929ca814b781619b8d730451c7ffef050059b0&Action=connect&DBUser=test_user&X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=test_id%2F20221104%2Fus-east-1%2Frds-db%2Faws4_request&X-Amz-Date=20221104T062611Z&X-Amz-Expires=900&X-Amz-SignedHeaders=host"

    assert.is_nil(err)
    assert.same(token, expected_auth_token)
  end)

  it("should expire token before credential expires", function ()
    -- Tick-tock till the environment credential is going to expire soon
    ngx.time = function () --luacheck: ignore
      return 1667543171 + environment_credential_expire - 16
    end
    ngx.now = function () --luacheck: ignore
      return 1667543171.0 + environment_credential_expire - 16
    end

    -- environment credential should be expire in 16 sec, so
    -- token1 should be expire in 1 sec
    local token1, err = iam_token_handler.get(mock_config_2)
    assert.is_nil(err)

    -- Modify time to 10 sec after env credential expire time
    -- So that we can generate a new presign url value
    ngx.time = function () --luacheck: ignore
      return 1667543171 + environment_credential_expire + 10
    end
    ngx.now = function () --luacheck: ignore
      return 1667543171.0 + environment_credential_expire + 10
    end

    -- Note that lrucache has local reference on ngx.now
    -- So our mock cannot take effect on that directly
    -- We need to wait for the expire time to pass
    assert.eventually(function ()
      -- Fetch token again, should be a new one
      local token2, err = iam_token_handler.get(mock_config_2)

      assert.is_nil(err)
      return token1 ~= token2
    end).with_step(0.5).with_timeout(2).is_truthy()
  end)

  it("should generate expected token with role assuming", function()
    local token, err = iam_token_handler.get(mock_config_assume_role)
    local expected_auth_token = "test_database.test_cluster.us-east-1.rds.amazonaws.com:443/?X-Amz-Signature=31aa805cd9c7e5929b4a0e25718d933d006ae130156f8b66b60861548fc771ce&Action=connect&DBUser=test_user&X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=test_access_key%2F20321101%2Fus-east-1%2Frds-db%2Faws4_request&X-Amz-Date=20321101T062621Z&X-Amz-Expires=900&X-Amz-Security-Token=%0A%20%20%20%20%20%20test_session_token%0A%20%20%20%20&X-Amz-SignedHeaders=host"

    assert.is_nil(err)
    assert.same(token, expected_auth_token)
    assert.same(is_custom_sts_endpoint_flag, false)
  end)

  it("should generate expected token with role assuming and custom sts endpoint", function()
    local token, err = iam_token_handler.get(mock_config_assume_role_with_sts_endpoint)
    local expected_auth_token = "test_database.test_cluster.us-east-1.rds.amazonaws.com:443/?X-Amz-Signature=31aa805cd9c7e5929b4a0e25718d933d006ae130156f8b66b60861548fc771ce&Action=connect&DBUser=test_user&X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=test_access_key%2F20321101%2Fus-east-1%2Frds-db%2Faws4_request&X-Amz-Date=20321101T062621Z&X-Amz-Expires=900&X-Amz-Security-Token=%0A%20%20%20%20%20%20test_session_token%0A%20%20%20%20&X-Amz-SignedHeaders=host"

    assert.is_nil(err)
    assert.same(token, expected_auth_token)
    assert.same(is_custom_sts_endpoint_flag, true)
  end)
end)
