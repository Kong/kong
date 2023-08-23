-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local http = require "resty.luasocket.http"
local json = require("cjson.safe")
local json_encode = json.encode
local json_decode = json.decode

local FAKE_TIMESTAMP = 1667543171

local mock_request
local original_new

local function mock_http_client()
  original_new = http.new
  http.new = function (self)
    local instance = original_new(self)
    instance.request_uri = mock_request
    return instance
  end
end


-- to get a definitive result
-- luacheck:ignore
ngx.time = function()
  return FAKE_TIMESTAMP
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

-- a random credential (not real)
local GCP_SERVICE_ACCOUNT_JSON = {
  type = "service_account",
  project_id = "test-box",
  private_key_id = "29a77b9062bf086d024129a77b9062bf086d0241",
  private_key = [[-----BEGIN PRIVATE KEY-----
MIIEvAIBADANBgkqhkiG9w0BAQEFAASCBKYwggSiAgEAAoIBAQDemN6pgqIFqY1x
fYtWGUfBzURQ+uOKYAED1oLXgMDnb4ocTZRo/UrR1VRfRaGbnUA5PCf2PiFVWojv
tplBNS//uGoQHXqBu1/AzD8Aujy/cw4AsIbuuRgNX9szb+63UZGX/tkW28682Zma
qWnANzApJN3joi3NG2YtLxGFd/RdwCLaOF6JiWoSPHLKc+DVr76gFejHInSI6S8n
/f29PAoI83KV9qv3L/THV/8FomMaBq9LlH+hOJEiifVPoo+OQfNIT9b3B0esQGfR
hhyHEFrwE28V7DAV04kjvlJCx9GMgBPRH7oycrn6E0y/bnPwjAFUlgHikHQ4tysE
IMiKoII3AgMBAAECggEAEmw0gXL+VdmiizIIxidxeOi0Lr+U9W7cpqSqT4uoa38f
vxfsoIPWHWe6g+gPaAGrvxDrfcXGnHnRu4UxSeRNBK0OmibWbMZFNn+w9y5yuKWd
ExGJGVjYVMMKMUeiSinGEv5UmT+37IlV3ScISZBHvCAA/UX+5GrQGg07NgCniNqm
ftaBFSSnEXHpmxkG9glx7Rp86J1TawtnyIMeMamF43JQ0qvfQnZ6Ycy6NzldjBHq
fJ4OGw//8Yc6aahXRHUdutyciA5TkMOHst9EP+WwC7/h2BdM1eCkYJHC1eZcJFMY
OekdHZOVK1G2jbyxKN17v4lgCYv8KylFYBGeQ9o6gQKBgQD2pE09MCG7azRfCVi/
rgXk10fezImxfrDopaKxrGDH3FWpUwHGgluTwZ9+AoaReB2H7XfV1PERgvpu2Ecq
9PRv3WG/MtxjxHJw7T3T8u3S/M5fsxno56nbFwWPinHQhE8Yz4TNk1Sz4HY18xD8
1H42st8gKMuKbkCc8ToSKE6PHQKBgQDnCwQN66LDglwiPlawrhAtTF9QEANtT8AS
N9YScqnRCwCCy8wGwxh+FT5bEUmomN/ISVHGEFVTwHMFSqwm0573trad9wGQIBtY
wrn6FMxx+5R3ONsbg519qYF5G5VXXxIuf6duMZX3DHN3fCoqk279XkNcrd/UTx1r
ppU7yiGyYwKBgE4bBeLEpUoGzxTxjstUvsUTb80clNZCup9SJM2DOzrPickPYlaM
3ZdTD8EF57uVgDSVfQeYYaccBVao4xC1ddsfDl9QKf7mLR+Z4aSHH81bBbfErgXV
pzKcfcRRIW3ZGHtQ7Et1xrMX+BdpnA2U9Us5JfO3N43lEE0jDzLE1Ov5AoGAZB/Y
/PNd0N5AcTKUvPJh3k+Xiom2AnwqH3sFEW+Reh8LdKM+4rtPdOxd3ndKdX7yk8h6
YJwZbjcbYXKv0g+pd24+C4zMp5nSYA/bKq4yvz6oY1ZHVdAewyNfEY3LlVaE+ZOm
ilGAzNQfgetUFqlX0wMzrAlJ06cJd+p0B7ocCkMCgYBYAx/JFcoTTadZ3uTPKMSE
4GGQIYtDZIA2tW4tRCBwbN53sfMUvcFHDhdwXzaUghvI81CPF4A7Go5D3xrpl1n9
d/kcHC783i7Vb9wkFHHiJxqK30LSflQRyVxFLaLbgs/v48VFncYEWoNXheC7yaSJ
9Omt1Z0SFusJIqmYK73U8g==
-----END PRIVATE KEY-----]],
  client_email = "admin@test-box.iam.gserviceaccount.com",
  client_id = "102038457501203826455",
  auth_uri = "https://accounts.google.com/o/oauth2/auth",
  token_uri = "https://oauth2.googleapis.com/token",
  auth_provider_x509_cert_url = "https://www.googleapis.com/oauth2/v1/certs",
  client_x509_cert_url = "https://www.googleapis.com/robot/v1/metadata/x509/admin%40test-box.iam.gserviceaccount.com"
}

local GCP_SERVICE_ACCOUNT = assert(json_encode(GCP_SERVICE_ACCOUNT_JSON))

local FAKE_TOKEN_JSON = {
  issued_at = FAKE_TIMESTAMP .. "123",
  scope = "READ",
  application_name = "ce1e94a2-9c3e-42fa-a2c6-1ee01815476b",
  refresh_token_issued_at = tostring((FAKE_TIMESTAMP .. "123") + 1000000),
  status = "approved",
  refresh_token_status = "approved",
  api_product_list = "[PremiumWeatherAPI]",
  expires_in = "1000000", --in seconds
  ["developer.mail"] = "tesla@weathersample.com",
  organization_id = "0",
  token_type = "BearerToken",
  refresh_token = "fYACGW7OCPtCNDEnRSnqFlEgogboFPMm",
  client_id = "5jUAdGv9pBouF0wOH5keAVI35GBtx3dT",
  access_token = "2l4IQtZXbn5WBJdL6EF7uenOWRsi",
  organization_name = "docs",
  refresh_token_expires_in = "86399", --in seconds
  refresh_count = "0"
}

local FAKE_TOKEN = assert(json_encode(FAKE_TOKEN_JSON))

local cred_success = false
local request
local response
-- we should return no token for "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token"
-- and then verify the jwt for "https://www.googleapis.com/oauth2/v4/token" and return a valid token
function mock_request(_, uri, req)
  uri = string.gsub(uri, "^[^/]+//[^/]+", "")
  if uri == "/computeMetadata/v1/instance/service-accounts/default/token" then
    return nil, "intentionally failed"

  elseif uri:find("/oauth2/v4/token") then
    local jwt = json_decode(req.body)
    assert.same("urn:ietf:params:oauth:grant-type:jwt-bearer", jwt.grant_type)
    assert.equal(762, #jwt.assertion)
    cred_success = true
    return {
      status = 200,
      body = FAKE_TOKEN,
      headers = { ["Content-Type"] = "application/json" },
    }

  else
    request = { uri = uri, req = req, }
    return response
  end
end


describe("cp outage handling storage support: #gcp", function()
  local gcp
  local gcp_instance

  lazy_setup(function()
    -- environment variables
    helpers.setenv("GCP_SERVICE_ACCOUNT", GCP_SERVICE_ACCOUNT)

    -- initialization
    mock_http_client()
  end)

  lazy_teardown(function()
    helpers.unsetenv("GCP_SERVICE_ACCOUNT")

    http.new = original_new
  end)

  before_each(function()
    local get_phase = ngx.get_phase
    ngx.get_phase = function() return "init" end -- luacheck: ignore
    package.loaded["kong.clustering.config_sync_backup.strategies.gcs"] = nil
    gcp = require "kong.clustering.config_sync_backup.strategies.gcs"
    ngx.get_phase = get_phase -- luacheck: ignore
    gcp.init_worker()
    gcp_instance = gcp.new("test_version", "gcs://test_bucket/test_prefix")
  end)

  it("upload", function ()
    cred_success = false
    request = nil
    response = {
      status = 200,
      body = "",
      headers = { ["Metadata-Flavor"] = "Google" },
    }

    helpers.wait_until(function ()
      gcp_instance:backup_config(test_config)
      return cred_success
    end, 2)

    assert.same({
      req = {
        body = test_config,
        headers = {
          Authorization = "Bearer 2l4IQtZXbn5WBJdL6EF7uenOWRsi",
          ["Content-Type"] = "application/json",
        },
        method = "POST",
        ssl_verify = true
      },
      uri = "/upload/storage/v1/b/test_bucket/o?name=test_prefix%2Ftest_version%2Fconfig.json"
    },
    request)
  end)

  it("download", function ()
    cred_success = false
    request = nil
    response = {
      status = 200,
      body = test_config,
      headers = {},
    }

    local result
    helpers.wait_until(function ()
      result = assert(gcp_instance:fetch_config())
      return cred_success
    end, 2)

    assert.same({
      req = {
        headers = {
          Authorization = "Bearer 2l4IQtZXbn5WBJdL6EF7uenOWRsi",
          ["Content-Type"] = "application/json",
        },
        method = "GET",
        ssl_verify = true
      },
      uri = "/storage/v1/b/test_bucket/o/test_prefix%2Ftest_version%2Fconfig.json?alt=media"
    },
    request)

    assert.equal(test_config, result)
  end)
end)
