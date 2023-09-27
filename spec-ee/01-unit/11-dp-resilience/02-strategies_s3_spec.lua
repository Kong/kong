-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require("spec.helpers")

local FAKE_TIMESTAMP = 1667543171
local original_time = ngx.time

-- make an assertion of what response we expect to see.
-- handle the detail of parsing the response line and subtle differencies
local function response_line_match(line, method, url)
  local m = assert(ngx.re.match(line, [[(.+) (.+) HTTP/1.1]]))
  assert.same(method, m[1])
  local url_extracted = m[2]
  -- a workaround for the subtle different behavior of different versions of `resty.http`:
  -- empty query table may lead to an URL with trailing `?` in earlier versions.
  if m[2]:sub(-1) == "?" then
    url_extracted = m[2]:sub(1, -2)
  end

  assert.same(url, url_extracted)
end

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
  assert.same("127.0.0.1:4566", headers.Host)
end

describe("cp outage handling storage support: #s3", function()
  local S3PORT = 4566
  local s3
  local s3_instance

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
    s3_instance = s3.new("test_version", "s3://test_bucket/test_prefix")
  end)

  it("upload", function ()
    -- mocking s3 server
    local mock_s3_server = helpers.http_server(S3PORT, { timeout = 10 })
    s3_instance:backup_config(test_config)
    local ok, lines, body, headers = mock_s3_server:join()
    assert(ok)
    response_line_match(lines[1], "PUT", "/test_bucket/test_prefix/test_version/config.json")
    assert.same("application/json", headers["Content-Type"])
    verify_aws_request(headers)

    assert.equal(test_config, body)
  end)

  it("download", function ()
    -- mocking s3 server
    local mock_s3_server = helpers.http_server(S3PORT, { timeout = 10, response = [[
HTTP/1.1 200 OK
Content-Length: 224

]] .. test_config })
    local result
    helpers.pwait_until(function()
      result = assert(s3_instance:fetch_config())
    end, 10)
    local ok, lines, body, headers = mock_s3_server:join()
    assert(ok)
    response_line_match(lines[1], "GET", "/test_bucket/test_prefix/test_version/config.json")
    verify_aws_request(headers)

    assert.equal(body, nil)
    assert.equal(test_config, result)
  end)
end)

-- we do not unit test gcp as it's more difficult and risky to mock. (We need to mock DNS for google at the test runner.)
