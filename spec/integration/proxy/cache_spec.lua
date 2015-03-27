local spec_helper = require "spec.spec_helpers"
local http_client = require "kong.tools.http_client"
local cjson = require "cjson"

local env = spec_helper.get_env()
local created_ids = {}

local kWebURL = spec_helper.API_URL
local kProxyURL = spec_helper.PROXY_URL

describe("Cache #cache", function()

  setup(function()
    spec_helper.prepare_db()
    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
    spec_helper.reset_db()
  end)

  it("should expire cache after five seconds", function()
    local response, status, headers = http_client.post(kWebURL.."/apis/", {
      name = "cache test",
      public_dns = "cache.test",
      target_url = "http://httpbin.org"
    })
    assert.are.equal(201, status)
    local api_id = cjson.decode(response).id
    assert.truthy(api_id)

    local response, status, headers = http_client.get(kProxyURL.."/get", {}, {host = "cache.test"})
    assert.are.equal(200, status)

    -- Let's add the authentication plugin configuration
    local response, status, headers = http_client.post(kWebURL.."/plugins_configurations/", {
      name = "headerauth",
      api_id = api_id,
      ["value.header_names"] = "x-key"
    })
    assert.are.equal(201, status)

    -- Making the request immediately after will succeed
    local response, status, headers = http_client.get(kProxyURL.."/get", {}, {host = "cache.test"})
    assert.are.equal(200, status)

    -- But waiting after the cache expiration (5 seconds) should block the request
    os.execute("sleep " .. tonumber(5))

    local response, status, headers = http_client.get(kProxyURL.."/get", {}, {host = "cache.test"})
    assert.are.equal(403, status)

    -- Create a consumer and an application will make it work again
    local response, status, headers = http_client.post(kWebURL.."/consumers/", {})
    assert.are.equal(201, status)
    local consumer_id = cjson.decode(response).id

    local response, status, headers = http_client.post(kWebURL.."/applications/", {
      consumer_id = consumer_id,
      public_key = "secret_key_123"
    })
    assert.are.equal(201, status)

    -- This should fail, wrong key
    local response, status, headers = http_client.get(kProxyURL.."/get", {}, {host = "cache.test", ["x-key"] = "secret_key"})
    assert.are.equal(403, status)

    -- This should work, right key
    local response, status, headers = http_client.get(kProxyURL.."/get", {}, {host = "cache.test", ["x-key"] = "secret_key_123"})
    assert.are.equal(200, status)
  end)

end)
