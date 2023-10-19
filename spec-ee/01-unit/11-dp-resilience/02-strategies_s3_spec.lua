-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require("spec.helpers")
local http_mock = require("spec.helpers.http_mock")

local FAKE_TIMESTAMP = 1667543171
local S3PORT = helpers.get_available_port()
local original_time = ngx.time

local URL = "/test_bucket/test_prefix/test_version/config.json"

local test_config = [[
{
  "version": "1.0",
  "services": [
    {
      "name": "mockbin",
      "url": "http://mockbin.com",
      "routes": [
        {
          "name": "mockbin-r1",
          "paths": ["/test1"]
        }
      ]
    }
  ]
}
]]

local function verify_aws_request(headers)
  assert(headers.Authorization:match(
    [[AWS4%-HMAC%-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/%d+/us%-east%-1/s3/aws4_request, SignedHeaders=[%-%w,;]+, Signature=%w+]]),
    headers.Authorization)
  assert(headers["X-Amz-Date"])
  assert(headers["X-Amz-Content-Sha256"])
  assert.same("127.0.0.1:" .. S3PORT, headers.Host)
end

describe("cp outage handling storage support: #s3", function()
  local s3
  local s3_instance
  local mock_s3_server

  lazy_setup(function()
    -- S3 environment variables
    helpers.setenv("AWS_REGION", "us-east-1")
    helpers.setenv("AWS_DEFAULT_REGION", "us-east-1")
    helpers.setenv("AWS_ACCESS_KEY_ID", "AKIAIOSFODNN7EXAMPLE")
    helpers.setenv("AWS_SECRET_ACCESS_KEY", "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY")
    helpers.setenv("AWS_CONFIG_STORAGE_ENDPOINT", "http://127.0.0.1:" .. S3PORT)

    -- to get a definitive result
    -- luacheck:ignore
    ngx.time = function()
      return FAKE_TIMESTAMP
    end

    -- initialization
    package.loaded["resty.aws"] = nil
    package.loaded["resty.aws.config"] = nil
    local get_phase = ngx.get_phase
    ngx.get_phase = function() return "init" end -- luacheck: ignore
    s3 = require "kong.clustering.config_sync_backup.strategies.s3"
    ngx.get_phase = get_phase -- luacheck: ignore
    s3.init_worker()
  end)

  lazy_teardown(function()
    -- luacheck:ignore
    ngx.time = original_time
  end)

  before_each(function()
    -- mocking s3 server
    mock_s3_server = http_mock.new(S3PORT, {
      [URL] = {
        access = [=[
          if ngx.req.get_method() == "GET" then
            ngx.print([[]=] ..
              test_config ..
            [=[]])
          end
          ngx.exit(ngx.HTTP_OK)
        ]=]
      },
    }, {
      log_opts = { req_body = true }
    })
    mock_s3_server:start()
    s3_instance = s3.new("test_version", "s3://test_bucket/test_prefix")
  end)

  after_each(function()
    mock_s3_server:stop(true)
  end)

  it("upload", function ()
    s3_instance:backup_config(test_config)

    local req = mock_s3_server:get_request()

    assert.same("PUT", req.method)
    assert.same(URL, req.uri)
    assert.same("application/json", req.headers["Content-Type"])
    verify_aws_request(req.headers)

    assert.equal(test_config, req.body)
  end)

  it("download", function ()
    local result
    helpers.pwait_until(function()
      result = assert(s3_instance:fetch_config())
    end, 10)

    local req = mock_s3_server:get_request()

    assert.same("GET", req.method)
    assert.same(URL, req.uri)
    verify_aws_request(req.headers)
    assert.equal("", req.body or "")

    assert.equal(test_config, result)
  end)
end)

-- we do not unit test gcp as it's more difficult and risky to mock. (We need to mock DNS for google at the test runner.)
